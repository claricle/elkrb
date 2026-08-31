# frozen_string_literal: true

require "yaml"

module Elkrb
  # @api private
  #
  # Shared "sniff JSON/YAML, fall back to ELKT" input-format detection.
  # Every command reads its input through here: Cli#read_input_file,
  # ConvertCommand#load_any_format, ValidateCommand#load_any_format and
  # DiagramCommand#load_graph. One tested home for logic all four call
  # sites need identical, instead of four private methods that can quietly
  # drift.
  #
  # The two paths guard differently, and only one of them is finished.
  # lutaml-model 0.8.19 succeeds on any YAML/JSON mapping, even one with no
  # recognized keys, and returns a graph with every field nil. The SNIFFED
  # path rejects that (hollow_model?). The DECLARED .json/.yml/.yaml path
  # applies the malformed-shape check only, so it does not. Measured:
  # `{"foo":1}` named .json and `foo: 1` named .yaml each exit 0 printing
  # `{}`, while the same bytes with no extension exit 1.
  #
  # That asymmetry is deliberate here, not an oversight -- this slice
  # scopes the hollow guard to the sniffed path in as many words. Widening
  # it to the declared path is a known limitation left to a later item.
  module FormatSniffer
    BYTE_ORDER_MARK = "\xEF\xBB\xBF".b.freeze
    private_constant :BYTE_ORDER_MARK

    UNPARSEABLE =
      "Unable to parse input file. Supported formats: JSON, YAML, ELKT"
    private_constant :UNPARSEABLE

    DOT_UNSUPPORTED =
      "DOT format input not yet supported. Use JSON, YAML, or ELKT."
    private_constant :DOT_UNSUPPORTED

    NIL_WHEN_HOLLOW = %i[
      id x y width height layout_options children edges properties
    ].freeze
    private_constant :NIL_WHEN_HOLLOW

    class << self
      # The single entry point every command reads input through. Extension
      # dispatch plus shape validation lived in four places and drifted apart;
      # a guard added to one silently left the other three open.
      #
      # The two paths raise differently, by design. A named JSON/YAML
      # extension hands lutaml-model the content directly, so a document it
      # cannot tokenize surfaces lutaml's own parse error, which names the
      # offending token, and a document Psych declines to load surfaces
      # Psych's own refusal. The sniffed path normalizes those to
      # UNPARSEABLE instead. The one refusal both paths share is the
      # SystemStackError rescue below, which the declared YAML branch
      # reaches as well.
      #
      # The byte order mark comes off here rather than per branch, because
      # every branch needs it gone and neither named branch stripped it.
      # `.json` was the loud half: lutaml hands the leading U+FEFF straight
      # to the JSON parser, which rejects the document. `.yml`/`.yaml` was
      # the quiet and more dangerous one -- Psych loads a marked document
      # and silently drops every key after the first, so a marked graph laid
      # out as an empty graph and the CLI exited 0. String#strip does NOT
      # remove a BOM, so it is no substitute.
      #
      # @param content [String] raw file content
      # @param extension [String] the file's downcased extension
      # @return [Elkrb::Graph::Graph, Hash] the parsed graph
      # @raise [Lutaml::Model::InvalidFormatError] when .json/.yml/.yaml
      #   content will not parse as that format
      # @raise [Psych::Exception] when .yml/.yaml content is valid YAML that
      #   Psych's safe loader refuses -- a !ruby/object tag
      #   (Psych::DisallowedClass) or an alias (Psych::AliasesNotEnabled)
      # @raise [ArgumentError] for .dot/.gv, for a parsed-but-unusable
      #   JSON/YAML model, for ELKT or sniffed content that yields nothing,
      #   and for YAML nested deeper than Psych's recursion can survive
      def read(content, extension)
        require_relative "graph/graph"

        read_by_extension(strip_byte_order_mark(content), extension)
      rescue SystemStackError
        # Psych recurses once per nesting level, so a few thousand open
        # brackets overflow the stack. SystemStackError is not a
        # StandardError, so it walked past every rescue below AND the CLI's
        # own, and the user got a raw trace. Caught here because this is
        # where the module states what it raises, and both the sniffed and
        # the declared YAML branch can reach it.
        raise ArgumentError, UNPARSEABLE
      end

      private

      # Every branch here runs inside #read's SystemStackError rescue, and
      # needs to: the declared .yml/.yaml branch overflows Psych's recursion
      # as readily as the sniffed one does.
      def read_by_extension(text, extension)
        case extension
        when ".json", ".yml", ".yaml" then read_model(text, extension)
        when ".elkt" then parse_elkt(text)
        when ".dot", ".gv" then raise ArgumentError, DOT_UNSUPPORTED
        else parse(text)
        end
      end

      # The mark is the three bytes EF BB BF, so it comes off by byte rather
      # than by character. String#delete_prefix compares CHARACTERS, and a
      # UTF-8 literal raises Encoding::CompatibilityError against a receiver
      # in another encoding that holds any non-ASCII byte -- File.read tags
      # content with Encoding.default_external, which the locale sets.
      #
      # @return [String] the content without its mark, in its own encoding
      def strip_byte_order_mark(content)
        return content unless content.byteslice(0, 3).b == BYTE_ORDER_MARK

        content.byteslice(3..)
      end

      # lutaml-model normalizes only the errors in its own
      # format_error_types list, measured at runtime as
      # Psych::SyntaxError, JSON::ParserError, NoMethodError,
      # Lutaml::Model::TypeError, ArgumentError, Moxml::ParseError,
      # Nokogiri::XML::SyntaxError. Psych's safe-load REFUSALS are not in
      # it, so a !ruby/object tag (Psych::DisallowedClass) or an alias
      # (Psych::AliasesNotEnabled) arrives here unconverted. Those are valid
      # YAML we decline to load, not "maybe this is ELKT" -- letting them fall
      # through would hand the text to the ELKT parser, which reads
      # `foo: 1` as layout option elk.foo and exits 0 on it. Normalize
      # here instead, so the caller sees the same message as any other
      # unreadable input.
      #
      # @param content [String] raw file content
      # @return [Elkrb::Graph::Graph, Hash] a parsed graph model, or an ELKT
      #   hash
      # @raise [ArgumentError] when neither JSON/YAML nor ELKT yields real
      #   content
      def parse(content)
        sniff(content) || parse_elkt_or_fail(content)
      rescue Psych::Exception
        raise ArgumentError, UNPARSEABLE
      end

      # JSON and YAML differ only in the deserializer; both then need the same
      # shape check.
      #
      # @raise [ArgumentError] when the document parses to an unusable model
      def read_model(content, extension)
        model = if extension == ".json"
                  Elkrb::Graph::Graph.from_json(content)
                else
                  Elkrb::Graph::Graph.from_yaml(content)
                end

        validate_model!(model)
      end

      # A file whose extension names the format skips sniffing, so it also
      # skips the malformed-shape check the sniffer applies. Both paths need
      # it: lutaml coerces a mapping where a sequence belongs into one
      # nil-filled model, and every downstream reader then breaks on it.
      #
      # @raise [ArgumentError] when the parsed model is not usable
      def validate_model!(graph)
        unless graph.is_a?(Elkrb::Graph::Graph) && !malformed_model?(graph)
          raise ArgumentError, UNPARSEABLE
        end

        graph
      end

      def parse_elkt(content)
        graph = parse_elkt!(content)
        if hollow_hash?(graph) && declarations?(content)
          raise ArgumentError, UNPARSEABLE
        end

        graph
      end

      # A JSON document can only open with `{` or `[`, so anything else goes
      # straight to YAML. Flow-style YAML opens with `{` too, though, so a
      # failed JSON parse has to fall through to YAML before ELKT gets a
      # turn -- otherwise a flow-style graph is read as ELKT layout options
      # and silently loses its children.
      def sniff(text)
        if text.lstrip.start_with?("{", "[")
          return try_json(text) || try_yaml(text)
        end

        try_yaml(text)
      end

      def try_json(text)
        real_graph(Elkrb::Graph::Graph.from_json(text))
      rescue Lutaml::Model::InvalidFormatError
        nil
      end

      def try_yaml(text)
        real_graph(Elkrb::Graph::Graph.from_yaml(text))
      rescue Lutaml::Model::InvalidFormatError
        nil
      end

      # A top-level sequence (`[]`, `[{}]`, `- id: g`) parses without raising
      # but comes back an Array, and lutaml-model 0.8.19 turns any mapping at
      # all into a Graph with every field nil. Neither is a real parse, and
      # calling #id on the Array would blow up.
      def real_graph(result)
        return nil unless result.is_a?(Elkrb::Graph::Graph)
        return nil if malformed_model?(result)

        result unless hollow_model?(result)
      end

      # Given a mapping where a sequence belongs (`"children": {"a": 1}`),
      # lutaml-model coerces it into ONE nil-filled model, so `children` comes
      # back as a single empty Node instead of a list. That is a malformed
      # document, not a graph: hand it back and every downstream reader breaks
      # on it. Fall through to the normalized parse error instead.
      def malformed_model?(graph)
        [graph.children, graph.edges].any? do |value|
          !value.nil? && !value.is_a?(::Array)
        end
      end

      # Mirrors the field list in Graph's json and yaml mapping blocks: when
      # every recognized field comes back nil, lutaml-model matched nothing
      # and the document was never understood. Present-but-empty is the
      # opposite of that -- `"children": []` and `"layoutOptions": {}` were
      # both recognized and are real content, so neither may read as hollow.
      # Deserialization leaves an absent field nil, and an explicit `null`
      # nil too, so a document carrying only those is still rejected.
      def hollow_model?(graph)
        NIL_WHEN_HOLLOW.all? { |field| graph.public_send(field).nil? }
      end

      # The sniffed path reaches ELKT only because nothing else could read
      # the document, and no extension declared it to be ELKT either. The
      # parser is lenient -- it skips every line it does not understand and
      # reads any `key: value` as a layout option -- so arbitrary text comes
      # back as a graph carrying junk options and no nodes. Requiring
      # children or edges is what keeps `layout garbage.txt` exiting 1.
      #
      # parse_elkt applies a looser guard on purpose: there the extension
      # names the format, so an options-only or geometry-only graph is
      # content the author meant to write.
      def parse_elkt_or_fail(content)
        graph = parse_elkt!(content)
        return graph unless childless?(graph)

        raise ArgumentError, UNPARSEABLE
      end

      def childless?(graph)
        blank?(graph[:children]) && blank?(graph[:edges])
      end

      def parse_elkt!(content)
        require_relative "parsers/elkt_parser"
        Elkrb::Parsers::ElktParser.parse(content)
      rescue StandardError
        raise ArgumentError, UNPARSEABLE
      end

      # Only parse_elkt consults this, and the scope matters. There the
      # extension declares the format, so an empty or comment-only file is a
      # valid empty graph and the hollow guard must not reject it. A file
      # that DOES carry declarations and still parses to nothing is
      # unrecognized content — the parser skips lines it does not
      # understand, so without this it exits 0 on junk.
      #
      # The sniffed path rejects both, because nothing there declares the
      # file to be ELKT in the first place. That is the same "two paths
      # raise differently, by design" rule #read states.
      def declarations?(text)
        text.gsub(%r{/\*.*?\*/}m, "")
          .each_line
          .any? { |line| !line.sub(%r{//.*$}, "").strip.empty? }
      end

      # An ELKT graph is itself a node and may carry only its own position or
      # size (`layout [ size: 30, 40 ]`). That is meaningful content, so the
      # root geometry counts alongside children, edges and options.
      #
      # This blank-checks the collections where hollow_model? nil-checks
      # them, and the difference is forced rather than an oversight. The ELKT
      # parser always fills children, edges and layoutOptions -- `foo: 1`
      # comes back as `children: [], edges: [], layoutOptions: {...}` -- so
      # nothing here is ever nil and emptiness is the only signal there is.
      # On the model path absence and emptiness are distinguishable, so an
      # empty collection means the document was understood.
      def hollow_hash?(graph)
        blank?(graph[:children]) && blank?(graph[:edges]) &&
          blank?(graph[:layoutOptions]) &&
          graph.values_at(:x, :y, :width, :height).all?(&:nil?)
      end

      def blank?(collection)
        collection.nil? || collection.empty?
      end
    end
  end
end
