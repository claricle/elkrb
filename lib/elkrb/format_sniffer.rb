# frozen_string_literal: true

require "json"
require "yaml"

module Elkrb
  # @api private
  #
  # Shared "sniff JSON/YAML, fall back to ELKT" input-format detection.
  # Every command reads its input through here: Cli#read_input_file,
  # ConvertCommand#load_any_format, ValidateCommand#load_any_format and
  # DiagramCommand#load_graph -- add a new one through this module too,
  # not a fifth private method, or its guards silently drift from the rest.
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

    # Psych's own nesting limit raises before the stack ever overflows, so
    # the SystemStackError rescue below never sees it. Matched by message
    # because the raising class, Psych::SyntaxError, is also what a
    # genuinely malformed document raises -- only the text tells them apart.
    NESTING_DEPTH_MESSAGE = "nesting depth exceeds the limit"
    private_constant :NESTING_DEPTH_MESSAGE

    class << self
      # The single entry point every command reads input through -- a guard
      # belongs here, not per command. String#strip does NOT remove a BOM,
      # so strip it here rather than per branch.
      #
      # @param content [String] raw file content
      # @param extension [String] the file's downcased extension
      # @return [Elkrb::Graph::Graph, Hash] the parsed graph
      # @raise [Lutaml::Model::InvalidFormatError] on unparseable JSON/YAML
      # @raise [Psych::Exception] when .yml/.yaml is valid YAML Psych refuses
      # @raise [ArgumentError] for .dot/.gv, an unusable JSON/YAML model,
      #   empty ELKT/sniffed content, or YAML nested past Psych's limit
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

      # Rescue Psych's safe-load refusals (a !ruby/object tag, an alias)
      # explicitly: they are not in lutaml-model's normalized-error list, and
      # falling through to the ELKT parser would read `foo: 1` as a layout
      # option and exit 0 on valid YAML we decline to load.
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
      # shape check. The charset is normalized before either deserializer
      # sees the content: a file tagged with a real source encoding other
      # than UTF-8 (ISO-8859-1, say) or with none at all (BINARY) otherwise
      # surfaces the parser's own encoding complaint instead of being read.
      #
      # @raise [ArgumentError] when the document parses to an unusable model,
      #   or is nested deeper than Psych's own limit allows
      def read_model(content, extension)
        text = normalize_charset(content)
        model = if extension == ".json"
                  Elkrb::Graph::Graph.from_json(text)
                else
                  Elkrb::Graph::Graph.from_yaml(text)
                end

        validate_model!(model, text, extension)
      rescue Lutaml::Model::InvalidFormatError => e
        raise ArgumentError, UNPARSEABLE if nesting_depth_exceeded?(e)

        raise
      end

      def nesting_depth_exceeded?(error)
        (error.cause || error).message.include?(NESTING_DEPTH_MESSAGE)
      end

      # content with a real, named source encoding is transcoded via
      # String#encode, which is what turns a Latin-1 0xE9 into the accented
      # character it actually names. UTF-8 and ASCII-8BIT carry no source
      # encoding to transcode FROM, so they are reinterpreted as UTF-8
      # directly; bytes that are not valid UTF-8 either way (a lone 0xE9
      # tagged BINARY, with no named encoding to recover one from) are
      # treated as Latin-1 as a last resort, since every byte value is a
      # valid Latin-1 character and the transcode can never itself fail.
      NO_SOURCE_ENCODING_TO_TRANSCODE_FROM =
        [Encoding::UTF_8, Encoding::ASCII_8BIT].freeze
      private_constant :NO_SOURCE_ENCODING_TO_TRANSCODE_FROM

      def normalize_charset(text)
        if NO_SOURCE_ENCODING_TO_TRANSCODE_FROM.include?(text.encoding)
          reinterpret_or_latin1(text)
        else
          begin
            text.encode(Encoding::UTF_8)
          rescue EncodingError
            text.dup.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
          end
        end
      end

      def reinterpret_or_latin1(text)
        reinterpreted = text.dup.force_encoding(Encoding::UTF_8)
        return reinterpreted if reinterpreted.valid_encoding?

        text.dup.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
      end

      # A file whose extension names the format skips sniffing, so it also
      # skips the malformed-shape check the sniffer applies. Both paths need
      # it: lutaml coerces a mapping where a sequence belongs into one
      # coerced model, and every downstream reader then breaks on it.
      #
      # @raise [ArgumentError] when the parsed model is not usable
      def validate_model!(graph, raw_content, extension)
        usable = graph.is_a?(Elkrb::Graph::Graph) &&
          !malformed_shape?(raw_content, extension) &&
          !hollow_model?(graph)
        raise ArgumentError, UNPARSEABLE unless usable

        graph
      end

      # A JSON document can only open with `{` or `[`, so anything else goes
      # straight to YAML. Flow-style YAML opens with `{` too, though, so a
      # failed JSON parse has to fall through to YAML before ELKT gets a
      # turn -- otherwise a flow-style graph is read as ELKT layout options
      # and silently loses its children.
      #
      # Normalized here for the same reason #read_model normalizes before
      # its own deserializer runs: a file with no extension to declare its
      # format still carries whatever charset it was written in, and
      # skipping this would read identical non-UTF-8 content differently
      # depending only on whether the caller happened to name the extension.
      def sniff(text)
        text = normalize_charset(text)

        if text.lstrip.start_with?("{", "[")
          return try_json(text) || try_yaml(text)
        end

        try_yaml(text)
      end

      def try_json(text)
        real_graph(Elkrb::Graph::Graph.from_json(text), text, ".json")
      rescue Lutaml::Model::InvalidFormatError
        nil
      end

      def try_yaml(text)
        real_graph(Elkrb::Graph::Graph.from_yaml(text), text, ".yaml")
      rescue Lutaml::Model::InvalidFormatError
        nil
      end

      # A top-level sequence (`[]`, `[{}]`, `- id: g`) parses without raising
      # but comes back an Array, and lutaml-model 0.8.19 turns any mapping at
      # all into a Graph with every field nil. Neither is a real parse, and
      # calling #id on the Array would blow up.
      def real_graph(result, raw_content, extension)
        return nil unless result.is_a?(Elkrb::Graph::Graph)
        return nil if malformed_shape?(raw_content, extension)

        result unless hollow_model?(result)
      end

      # Given a mapping where a sequence belongs (`"children": {"a": 1}`),
      # lutaml-model's coercion of it can be indistinguishable from a
      # legitimate value by the time it reaches the parsed MODEL -- a
      # coerced `Geometry::Point` defaults its x/y to 0.0, not nil, so it
      # reads exactly like a real point at the origin. The check runs
      # against the RAW parsed document instead, before any of that
      # coercion happens.
      #
      # The key list mirrors every `collection: true` attribute in graph/,
      # by both its JSON and its YAML spelling.
      COLLECTION_KEYS = %w[
        children edges labels ports sections sources targets
        bendPoints bend_points
        incomingSections incoming_sections
        outgoingSections outgoing_sections
        junctionPoints junction_points
      ].freeze
      private_constant :COLLECTION_KEYS

      # properties and layout_options are declared `:hash` on every model
      # (Graph, Node, Edge, Label) -- an opaque caller-defined bag, not part
      # of the graph schema. A key the caller chose for their own metadata
      # can coincidentally match a COLLECTION_KEYS name ("properties":
      # {"children": "metadata"}); checking inside the bag against the
      # schema's own key list is a false positive, not a malformed document.
      OPAQUE_METADATA_KEYS = %w[properties layoutOptions layout_options].freeze
      private_constant :OPAQUE_METADATA_KEYS

      # @return [Boolean] true when a collection key, at any depth, holds
      #   something other than a sequence or an absent/null value
      def malformed_shape?(raw_content, extension)
        raw = parse_raw_structure(raw_content, extension)
        return false if raw.nil?

        raw_shape_malformed?(raw)
      end

      # A parse failure here is not this check's to report: the real
      # deserializer already ran (successfully, to reach this point) or its
      # own failure is handled by its own caller. Either way, nothing to
      # compare the model's shape against, so the model is taken as given.
      def parse_raw_structure(content, extension)
        extension == ".json" ? ::JSON.parse(content) : ::YAML.safe_load(content)
      rescue StandardError
        nil
      end

      def raw_shape_malformed?(node)
        case node
        when ::Hash
          hash_shape_malformed?(node)
        when ::Array
          node.any? { |item| raw_shape_malformed?(item) }
        else
          false
        end
      end

      def hash_shape_malformed?(node)
        return true if collection_key_malformed?(node)

        node.each_pair.any? do |key, value|
          next false if OPAQUE_METADATA_KEYS.include?(key)

          raw_shape_malformed?(value)
        end
      end

      def collection_key_malformed?(node)
        COLLECTION_KEYS.any? do |key|
          node.key?(key) && !node[key].nil? && !node[key].is_a?(::Array)
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
      # the document, and no extension declared it to be ELKT either, so a
      # childless, edgeless result is rejected as "probably not meant to be
      # ELKT" -- that is what keeps `layout garbage.txt` exiting 1. Keep the
      # generic UNPARSEABLE message even for a located Elkrb::ParseError:
      # nothing here told the user this was ELKT, so a location inside a
      # grammar they never invoked is not actionable.
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

      # Raises whatever the real parser raised, unwrapped: an
      # Elkrb::ParseError (location-bearing) or the Lexer's `TypeError` for
      # non-String input. Callers decide how much to keep --
      # `parse_elkt_declared!` below keeps the location, `parse_elkt_or_fail`
      # above discards it.
      def parse_elkt!(content)
        require_relative "parsers/elkt_parser"
        Elkrb::Parsers::ElktParser.parse(content)
      end

      # The declared `.elkt` path: the extension names the format, so the
      # located Elkrb::ParseError message ("...at line 4, column 9") is kept
      # rather than replaced with the generic UNPARSEABLE text. Only
      # ParseError gets this treatment -- the Lexer's `TypeError` for a
      # non-String input has no location to report, so the generic message
      # is the correct fallback for it.
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
