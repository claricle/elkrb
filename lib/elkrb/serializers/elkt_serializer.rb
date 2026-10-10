# frozen_string_literal: true

require "json"
require_relative "../errors"

module Elkrb
  module Serializers
    # Serializes graph models and Hashes to ELK Text.
    class ElktSerializer
      IDENTIFIER = /\A[A-Za-z_]\w*\z/
      PROPERTY_SEGMENT = /\A[A-Za-z_]\w*\z/
      KEYWORDS = %w[
        graph node port label edge layout section position size
        start end bends incoming outgoing true false null
      ].freeze
      LABEL_ESCAPES = {
        "\\" => "\\\\", '"' => '\\"', "\n" => "\\n", "\r" => "\\r",
        "\t" => "\\t", "\b" => "\\b", "\f" => "\\f"
      }.freeze
      private_constant :IDENTIFIER, :PROPERTY_SEGMENT, :KEYWORDS, :LABEL_ESCAPES

      def initialize(options = {})
        @indent_size = options[:indent_size] || 2
      end

      def serialize(graph, _options = {})
        @indent_level = 0
        @output = []
        @graph_hash = graph_hash(graph)
        @scope_stack = []
        prepare_ids(@graph_hash)
        emit_root(@graph_hash)
        "#{@output.join("\n")}\n"
      end

      private

      def graph_hash(graph)
        return graph if graph.is_a?(Hash)
        return JSON.parse(graph.to_json, symbolize_names: true) if
          graph.respond_to?(:to_json)

        graph
      end

      def emit_root(graph)
        id = value(graph, :id)
        @output << "graph #{mapped_id(id)}" if id
        with_scope(graph) do
          serialize_shape_layout(graph)
          serialize_graph(graph)
        end
      end

      def serialize_graph(graph)
        options = value(graph, :layoutOptions) || {}
        serialize_layout_options(options)
        @output << "" if options.any?

        labels = value(graph, :labels) || []
        ports = value(graph, :ports) || []
        children = value(graph, :children) || []
        edges = value(graph, :edges) || []
        labels.each { |label| serialize_label(label) }
        ports.each { |port| serialize_port(port) }
        children.each { |node| serialize_node(node) }
        @output << "" if children.any? && edges.any?
        edges.each { |edge| serialize_edge(edge) }
      end

      def serialize_layout_options(options)
        indent = indentation
        options.each do |key, option_value|
          @output << "#{indent}#{property_key(key)}: " \
                     "#{format_value(option_value)}"
        end
      end

      def serialize_node(node)
        id = mapped_id(value(node, :id))
        if node_has_block?(node)
          open_block("node #{id}") { serialize_node_block(node) }
        else
          @output << "#{indentation}node #{id}"
        end
      end

      def node_has_block?(node)
        shape_layout_parts(node).any? ||
          collection?(node, :labels) || collection?(node, :ports) ||
          collection?(node, :children) || collection?(node, :edges) ||
          hash_present?(node, :layoutOptions)
      end

      def serialize_node_block(node)
        with_scope(node) do
          serialize_shape_layout(node)
          serialize_layout_options(value(node, :layoutOptions) || {})
          (value(node, :labels) || []).each { |label| serialize_label(label) }
          (value(node, :ports) || []).each { |port| serialize_port(port) }
          (value(node, :children) || []).each { |child| serialize_node(child) }
          (value(node, :edges) || []).each { |edge| serialize_edge(edge) }
        end
      end

      def serialize_port(port)
        id = mapped_id(value(port, :id))
        if port_has_block?(port)
          open_block("port #{id}") { serialize_port_block(port) }
        else
          @output << "#{indentation}port #{id}"
        end
      end

      def port_has_block?(port)
        shape_layout_parts(port).any? || collection?(port, :labels) ||
          hash_present?(port, :layoutOptions)
      end

      def serialize_port_block(port)
        serialize_shape_layout(port)
        serialize_layout_options(value(port, :layoutOptions) || {})
        (value(port, :labels) || []).each { |label| serialize_label(label) }
      end

      def serialize_edge(edge)
        sources = serialized_endpoints(edge, :source)
        targets = serialized_endpoints(edge, :target)
        id = value(edge, :id)
        prefix = id ? "#{mapped_id(id)}: " : ""
        declaration = "edge #{prefix}#{sources.join(', ')} -> " \
                      "#{targets.join(', ')}"

        if edge_has_block?(edge)
          open_block(declaration) { serialize_edge_block(edge) }
        else
          @output << "#{indentation}#{declaration}"
        end
      end

      def edge_has_block?(edge)
        hash_present?(edge, :layoutOptions) || collection?(edge, :labels) ||
          collection?(edge, :sections)
      end

      def serialize_edge_block(edge)
        emit_sections(value(edge, :sections)) if collection?(edge, :sections)
        serialize_layout_options(value(edge, :layoutOptions) || {})
        (value(edge, :labels) || []).each { |label| serialize_label(label) }
      end

      def emit_sections(sections)
        @output << "#{indentation}layout ["
        @indent_level += 1
        used_ids = sections.filter_map do |section|
          id = value(section, :id)
          mapped_id(id) if id
        end.to_h { |id| [id, true] }
        sections.each_with_index do |section, index|
          emit_section(section, sections.length, index, used_ids)
        end
        @indent_level -= 1
        @output << "#{indentation}]"
      end

      def emit_section(section, count, index, used_ids)
        id = value(section, :id)
        return emit_section_body(section) if count == 1 && !id

        id ||= available_section_id(index + 1, used_ids)
        used_ids[mapped_id(id)] = true
        outgoing = Array(value(section, :outgoingSections))
        declaration = "section #{mapped_id(id)}"
        if outgoing.any?
          refs = outgoing.map { |ref| mapped_id(ref) }.join(", ")
          declaration = "#{declaration} -> #{refs}"
        end
        @output << "#{indentation}#{declaration} ["
        @indent_level += 1
        emit_section_body(section)
        @indent_level -= 1
        @output << "#{indentation}]"
      end

      def emit_section_body(section)
        emit_shape_reference(section, :incomingShape, "incoming")
        emit_shape_reference(section, :outgoingShape, "outgoing")
        emit_section_point(section, :startPoint, "start")
        emit_section_point(section, :endPoint, "end")
        bends = Array(value(section, :bendPoints))
        unless bends.empty?
          points = bends.map { |point| formatted_point(point) }.join(" | ")
          @output << "#{indentation}bends: #{points}"
        end
        serialize_layout_options(value(section, :layoutOptions) || {})
      end

      def available_section_id(index, used_ids)
        loop do
          candidate = "_section#{index}"
          return candidate unless used_ids.key?(mapped_id(candidate))

          index += 1
        end
      end

      def emit_shape_reference(section, key, name)
        reference = value(section, key)
        return unless reference

        @output << "#{indentation}#{name}: #{endpoint(reference)}"
      end

      def emit_section_point(section, key, name)
        point = value(section, key)
        return unless point

        @output << "#{indentation}#{name}: #{formatted_point(point)}"
      end

      def formatted_point(point)
        "#{format_number(value(point, :x))}, #{format_number(value(point, :y))}"
      end

      def serialize_label(label)
        id = value(label, :id)
        prefix = id ? "#{mapped_id(id)}: " : ""
        declaration = "label #{prefix}\"#{escape_label(value(label, :text))}\""

        if label_has_block?(label)
          open_block(declaration) do
            serialize_shape_layout(label)
            serialize_layout_options(value(label, :layoutOptions) || {})
          end
        else
          @output << "#{indentation}#{declaration}"
        end
      end

      def label_has_block?(label)
        shape_layout_parts(label).any? || hash_present?(label, :layoutOptions)
      end

      def serialize_shape_layout(shape)
        parts = shape_layout_parts(shape)
        @output << "#{indentation}layout [ #{parts.join('  ')} ]" if parts.any?
      end

      # Position first, then size: this is the order ELK itself writes.
      def shape_layout_parts(shape)
        parts = []
        x = value(shape, :x)
        y = value(shape, :y)
        width = value(shape, :width)
        height = value(shape, :height)
        parts << "position: #{format_number(x)}, #{format_number(y)}" if x && y
        if width && height
          parts << "size: #{format_number(width)}, #{format_number(height)}"
        end
        parts
      end

      def open_block(declaration)
        @output << "#{indentation}#{declaration} {"
        @indent_level += 1
        yield
        @indent_level -= 1
        @output << "#{indentation}}"
      end

      def endpoint(id)
        @scope_stack.reverse_each do |scope|
          return scope[id.to_s] if scope.key?(id.to_s)
        end
        mapped_id(id)
      end

      def serialized_endpoints(edge, direction)
        port = value(edge, :"#{direction}Port")
        node = Array(value(edge, :"#{direction}s")).first ||
          value(edge, direction)
        return ["#{mapped_id(node)}.#{mapped_id(port)}"] if port

        Array(value(edge, :"#{direction}s")).map { |id| endpoint(id) }
      end

      def prepare_ids(graph)
        ids = []
        graph_id = value(graph, :id)&.to_s
        ids << graph_id if graph_id
        collect_ids(graph, ids)
        collect_root_port_ids(graph, ids)
        @id_map = {}
        used = {}

        valid, invalid = ids.uniq.partition { |id| valid_identifier?(id) }
        valid.each do |id|
          @id_map[id] = id
          used[id] = true
        end

        invalid.each do |id|
          base = sanitized_id(id)
          candidate = base
          counter = 2
          while used[candidate]
            candidate = "#{base}_#{counter}"
            counter += 1
          end
          @id_map[id] = candidate
          used[candidate] = true
        end
      end

      def collect_ids(container, ids = [])
        collect_member_ids(value(container, :labels), ids)
        collect_edge_ids(value(container, :edges), ids)
        Array(value(container, :children)).each do |node|
          node_id = value(node, :id)&.to_s
          ids << node_id if node_id
          Array(value(node, :ports)).each do |port|
            port_id = value(port, :id)&.to_s
            next unless port_id

            ids << port_id
            collect_member_ids(value(port, :labels), ids)
          end
          collect_ids(node, ids)
        end
        ids
      end

      def collect_root_port_ids(graph, ids)
        Array(value(graph, :ports)).each do |port|
          port_id = value(port, :id)&.to_s
          ids << port_id if port_id
          collect_member_ids(value(port, :labels), ids)
        end
      end

      def collect_edge_ids(edges, ids)
        Array(edges).each do |edge|
          edge_id = value(edge, :id)&.to_s
          ids << edge_id if edge_id
          collect_member_ids(value(edge, :labels), ids)
          collect_member_ids(value(edge, :sections), ids)
        end
      end

      def with_scope(container)
        @scope_stack << endpoint_scope(container)
        yield
      ensure
        @scope_stack.pop
      end

      def endpoint_scope(container)
        scope = {}
        children = Array(value(container, :children))
        children.each do |child|
          id = value(child, :id)
          scope[id.to_s] ||= mapped_id(id) if id
        end
        Array(value(container, :ports)).each do |port|
          id = value(port, :id)
          scope[id.to_s] ||= mapped_id(id) if id
        end
        children.each do |child|
          owner = value(child, :id)
          Array(value(child, :ports)).each do |port|
            id = value(port, :id)
            next unless owner && id

            scope[id.to_s] ||= "#{mapped_id(owner)}.#{mapped_id(id)}"
          end
        end
        scope
      end

      def collect_member_ids(members, ids)
        Array(members).each do |member|
          id = value(member, :id)&.to_s
          ids << id if id
        end
      end

      def mapped_id(id)
        @id_map.fetch(id.to_s, sanitized_id(id.to_s))
      end

      def valid_identifier?(id)
        IDENTIFIER.match?(id) && !KEYWORDS.include?(id)
      end

      def sanitized_id(id)
        sanitized = id.gsub(/\W/, "_")
        sanitized = "_#{sanitized}" unless sanitized.match?(/\A[A-Za-z_]/)
        sanitized = "_#{sanitized}" if KEYWORDS.include?(sanitized)
        sanitized.empty? ? "_id" : sanitized
      end

      def property_key(key)
        segments = key.to_s.split(".", -1)
        unless segments.all? { |segment| PROPERTY_SEGMENT.match?(segment) }
          raise Elkrb::ValidationError,
                "ELKT cannot represent option key #{key.inspect}"
        end

        segments.map do |segment|
          KEYWORDS.include?(segment) ? "^#{segment}" : segment
        end.join(".")
      end

      def format_value(option_value)
        case option_value
        when Float then format_number(option_value)
        when Integer, TrueClass, FalseClass then option_value.to_s
        when NilClass then "null"
        else format_string_value(option_value.to_s)
        end
      end

      def format_string_value(text)
        return text if valid_value_identifier?(text)

        "\"#{escape_label(text)}\""
      end

      def valid_value_identifier?(text)
        text.split(".").all? { |part| valid_identifier?(part) }
      end

      def escape_label(text)
        text.to_s.gsub(/[\\"\n\r\t\x08\f]/) { |char| LABEL_ESCAPES.fetch(char) }
      end

      def format_number(number)
        unless number.respond_to?(:finite?) && number.finite?
          raise Elkrb::ValidationError,
                "ELKT numbers must be finite, got #{number.inspect}"
        end

        return number.to_i.to_s if number.is_a?(Float) && number == number.to_i

        number.to_s
      end

      def indentation
        " " * (@indent_level * @indent_size)
      end

      def collection?(object, key)
        Array(value(object, key)).any?
      end

      def hash_present?(object, key)
        (value(object, key) || {}).any?
      end

      def value(object, key)
        return object[key] if object.key?(key)

        object[key.to_s]
      end
    end
  end
end
