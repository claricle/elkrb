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
  # Both paths guard the same way, and that is load-bearing.
  # lutaml-model 0.8.19 succeeds on any YAML/JSON mapping, even one with no
  # recognized keys, and returns a graph with every field nil. Both the
  # SNIFFED path and the DECLARED .json/.yml/.yaml path reject that, via
  # hollow_model?.
  #
  # The declared path used to skip it, which made the guard true in one
  # direction only: `{"foo":1}` named .json exited 0 printing `{}` while the
  # SAME BYTES with no extension exited 1. An earlier slice scoped the hollow
  # check to the sniffed path deliberately and left widening it to a later
  # item; review rated the resulting hole a High, so it is closed here rather
  # than deferred again. Measured after the change: both namings exit 1, and
  # the fixture corpus still loads.
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
        when ".elkt" then parse_elkt_declared!(text)
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
        usable = graph.is_a?(Elkrb::Graph::Graph) &&
          !malformed_model?(graph) &&
          !hollow_model?(graph)
        raise ArgumentError, UNPARSEABLE unless usable

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
      # Walks the WHOLE model, and every collection field on it.
      #
      # lutaml coerces a mapping where a sequence belongs, at every level and
      # in every field: a nested `"children": {...}` comes back as a single
      # Node, an edge's `"sources": {...}` as a String, and a node's
      # `"labels": {...}` as a single Label. Checking only children and edges
      # let the rest through -- `validate` printed "is valid" for an
      # object-valued `labels` and `layout` then died with
      # `undefined method 'empty?' for an instance of Elkrb::Graph::Label`.
      #
      # The field list is every `collection: true` attribute in graph/.
      COLLECTIONS = %i[
        children edges labels ports sections sources targets bend_points
      ].freeze
      private_constant :COLLECTIONS

      def malformed_model?(node)
        values = present_collections(node)
        return true if values.any? { |value| !value.is_a?(::Array) }

        # Recurse only through a value already known to be an Array --
        # otherwise the walk would iterate the very value it just rejected.
        values.any? { |value| value.any? { |item| nested_malformed?(item) } }
      end

      def present_collections(node)
        COLLECTIONS.filter_map do |field|
          node.public_send(field) if node.respond_to?(field)
        end
      end

      def nested_malformed?(item)
        return false unless COLLECTIONS.any? { |field| item.respond_to?(field) }

        malformed_model?(item)
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
      # the document, and no extension declared it to be ELKT either, so a
      # childless, edgeless result is treated as "probably not meant to be
      # ELKT" rather than a real graph -- requiring children or edges is
      # what keeps `layout garbage.txt` exiting 1. This is a deliberate
      # policy for the UNDECLARED case, not primarily a garbage filter: the
      # strict grammar (see parse_elkt! below) already raises directly on
      # content it cannot parse at all.
      #
      # The message stays the generic UNPARSEABLE one here even when the
      # parser raised a located Elkrb::ParseError -- unlike the declared
      # path below, nothing here told the user this was ELKT, so a location
      # inside an ELKT grammar they never invoked is not something they can
      # act on. `spec/elkrb/cli/shell_boundary_spec.rb`'s "an empty but
      # recognized collection" and "top-level JSON/YAML sequence" examples
      # pin this on the sniffed path specifically.
      def parse_elkt_or_fail(content)
        graph = parse_elkt!(content)
        return graph unless childless?(graph)

        reject_unparseable!
      rescue StandardError
        reject_unparseable!
      end

      def reject_unparseable!
        raise ArgumentError, UNPARSEABLE
      end

      def childless?(graph)
        blank?(graph[:children]) && blank?(graph[:edges])
      end

      # PR #17 rewrote the ELKT grammar to be strict: a line that matches no
      # production raises Elkrb::ParseError directly (verified --
      # "xyzzy foo bar" and every other unrecognized-line shape we tried all
      # raise "expected node, port, label, edge..." rather than being
      # silently skipped). The OLD parser was lenient and swallowed anything
      # it did not recognize, which is why this module used to carry a
      # separate "hollow result" guard for the declared .elkt path --
      # `hollow_hash?`, `declarations?` and friends, removed here. A
      # StandardError from the new parser (ParseError included) already
      # reports refusal; there is no longer a silent-junk case for the
      # declared path to catch. The SNIFFED path keeps its own guard,
      # `childless?` above -- that one is about a graph legitimately parsing
      # to nothing when nothing declared it to be ELKT in the first place,
      # which strict grammar does not change.
      #
      # Raises whatever the real parser raised, unwrapped: an
      # Elkrb::ParseError (location-bearing) or the Lexer's `TypeError` for
      # non-String input. Callers decide how much of that to keep --
      # `parse_elkt_declared!` below keeps the location, `parse_elkt_or_fail`
      # above discards it.
      def parse_elkt!(content)
        require_relative "parsers/elkt_parser"
        Elkrb::Parsers::ElktParser.parse(content)
      end

      # The declared `.elkt` path: the extension names the format, so the
      # located Elkrb::ParseError message ("...at line 4, column 9") is
      # something the author can act on directly, and it is kept. Losing it
      # and substituting the generic UNPARSEABLE text was the actual defect
      # -- the CLI already writes to stderr on purpose (commit eefcfd1), so
      # keeping the location keeps BOTH the deliberate stream and the
      # diagnostic detail, instead of trading one for the other.
      #
      # Only ParseError gets this treatment. The one other StandardError the
      # real parser can raise, Lexer's `TypeError` for non-String input, has
      # no location to report -- the generic message is the correct
      # fallback for it, not a narrower case of the same bug.
      def parse_elkt_declared!(content)
        parse_elkt!(content)
      rescue Elkrb::ParseError => e
        raise ArgumentError, e.message
      rescue StandardError
        raise ArgumentError, UNPARSEABLE
      end

      def blank?(collection)
        collection.nil? || collection.empty?
      end
    end
  end
end
