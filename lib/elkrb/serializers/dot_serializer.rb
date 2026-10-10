# frozen_string_literal: true

require_relative "../options/resolver"

module Elkrb
  module Serializers
    # Serializes ELK graphs to Graphviz DOT format
    #
    # This serializer converts ELK graph structures into DOT format strings
    # that can be rendered by Graphviz. It supports:
    # - Node and edge declarations with attributes
    # - Hierarchical graphs (subgraphs/clusters)
    # - Labels and ports
    # - Layout direction and other properties
    #
    # @example Basic usage
    #   serializer = DotSerializer.new
    #   dot_string = serializer.serialize(graph)
    #   File.write("output.dot", dot_string)
    #
    # @example With options
    #   serializer = DotSerializer.new
    #   dot_string = serializer.serialize(graph,
    #     directed: true,
    #     rankdir: "TB"
    #   )
    class DotSerializer
      HtmlValue = Data.define(:text)
      private_constant :HtmlValue

      # Default indentation width for DOT output
      INDENT_WIDTH = 2

      # @param graph [Elkrb::Graph::Graph] The graph to serialize
      # @param options [Hash] Serialization options
      # @option options [Boolean] :directed (true) Whether graph is directed
      # @option options [String] :rankdir Layout direction (TB, LR, BT, RL)
      # @option options [String] :graph_name Name for the graph
      # @option options [Hash] :graph_attrs Additional graph attributes
      # @option options [Hash] :node_attrs Default node attributes
      # @option options [Hash] :edge_attrs Default edge attributes
      # @return [String] DOT format string
      def serialize(graph, options = {})
        @options = {
          directed: true,
          rankdir: nil,
          graph_name: "G",
          graph_attrs: {},
          node_attrs: {},
          edge_attrs: {},
          engine: nil,
        }.merge(options)

        @indent_level = 0

        # Convert hash to Graph if needed
        @graph = graph.is_a?(Hash) ? hash_to_graph(graph) : graph
        index_endpoints(@graph)
        @scope_stack = [@endpoint_scopes.fetch(@graph)]

        lines = []
        lines << graph_declaration
        lines << "{"

        @indent_level += 1

        # Graph attributes
        lines.concat(format_graph_attributes(@graph))

        # Default node and edge attributes
        lines << indent("node #{format_attrs(@options[:node_attrs])}") unless
          @options[:node_attrs].empty?
        lines << indent("edge #{format_attrs(@options[:edge_attrs])}") unless
          @options[:edge_attrs].empty?

        # Process children (nodes)
        if @graph.children && !@graph.children.empty?
          @graph.children.each do |node|
            lines.concat(format_node(node))
          end
        end

        # Process edges
        if @graph.edges && !@graph.edges.empty?
          @graph.edges.each do |edge|
            lines.concat(format_edge(edge))
          end
        end

        @indent_level -= 1
        lines << "}"

        lines.join("\n")
      end

      private

      def hash_to_graph(hash)
        require_relative "../graph/graph"
        Elkrb::Graph::Graph.from_hash(hash)
      end

      # Generate graph declaration
      def graph_declaration
        type = @options[:directed] ? "digraph" : "graph"
        "#{type} #{quote_id(@options[:graph_name])}"
      end

      # Format graph-level attributes
      def format_graph_attributes(graph)
        attrs = @options[:graph_attrs].dup
        attrs[:compound] = true if @clusters.any?

        # Add rankdir from options or graph layout options
        if @options[:rankdir]
          attrs[:rankdir] = @options[:rankdir]
        elsif (direction = option_resolver.get("elk.direction", graph,
                                               default: nil))
          attrs[:rankdir] = elk_direction_to_rankdir(direction)
        end

        # Add graph size if specified
        if graph.width && graph.height && graph.width.positive? && graph.height.positive?
          # Convert to inches (DOT uses inches by default)
          attrs[:size] = "#{graph.width / 72},#{graph.height / 72}"
        end

        # Output graph attributes
        attrs.map do |key, value|
          indent("#{key}=#{quote_value(value)}")
        end
      end

      # Format a node with all its properties
      def format_node(node, _parent_id = nil)
        lines = []

        # Hierarchical node - create a subgraph
        if node.hierarchical?
          lines.concat(format_subgraph(node))
        else
          # Simple node
          node_id = quote_id(@node_names.fetch(node))
          attrs = build_node_attributes(node)

          lines << indent("#{node_id} #{format_attrs(attrs)}")
        end

        lines
      end

      # Format a subgraph (hierarchical node)
      def format_subgraph(node)
        lines = []
        cluster_id = @clusters.fetch(node)

        lines << indent("subgraph #{cluster_id} {")
        @indent_level += 1

        # Subgraph label
        if node.labels && !node.labels.empty?
          lines << indent("label=#{quote_labels(node.labels.map(&:text))}")
        end

        with_endpoint_scope(node) do
          # Process children
          if node.children && !node.children.empty?
            node.children.each do |child|
              lines.concat(format_node(child, node.id))
            end
          end

          # Process edges within this subgraph
          if node.edges && !node.edges.empty?
            node.edges.each do |edge|
              lines.concat(format_edge(edge))
            end
          end
        end

        @indent_level -= 1
        lines << indent("}")

        lines
      end

      # Build node attribute hash
      def build_node_attributes(node)
        attrs = {}

        # Label
        if node.labels && !node.labels.empty?
          attrs[:label] = node.labels.map(&:text)
        elsif node.id
          attrs[:label] = [node.id]
        end

        # Size (DOT uses inches)
        if node.width && node.height && node.width.positive? && node.height.positive?
          attrs[:width] = (node.width / 72.0).round(2)
          attrs[:height] = (node.height / 72.0).round(2)
          attrs[:fixedsize] = "true"
        end

        # Position (if laid out)
        if neato? && node.x && node.y
          # DOT uses center coordinates, ELK uses top-left
          # Also need to account for height since DOT y goes up
          center_x = node.x + ((node.width || 0) / 2.0)
          center_y = node.y + ((node.height || 0) / 2.0)
          attrs[:pos] = "#{center_x.round(2)},#{center_y.round(2)}!"
        end

        # Shape
        attrs[:shape] = "box" # Default shape for ELK nodes

        # Properties
        if node.properties && node.properties["dot.shape"]
          attrs[:shape] = node.properties["dot.shape"]
        end

        apply_port_label(attrs, node) if declared_ports(node).any?

        attrs
      end

      def apply_port_label(attrs, node)
        attrs[:label] = HtmlValue.new(html_port_label(node))
      end

      def html_port_label(node)
        labels = Array(node.labels).map(&:text)
        labels = [node.id] if labels.empty?
        label = labels.map { |text| html_escape(text) }.join("<BR/>")
        ports = declared_ports(node).map do |port_id, name|
          %(<TD PORT="#{name}" TOOLTIP="#{html_escape(port_id)}"></TD>)
        end.join
        "<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\"" \
          "#{html_table_dimensions(node)}>" \
          "<TR><TD>#{label}</TD></TR><TR>#{ports}</TR></TABLE>>"
      end

      def html_table_dimensions(node)
        return "" unless node.width&.positive? && node.height&.positive?

        width = node.width.ceil
        height = node.height.ceil
        %( WIDTH="#{width}" HEIGHT="#{height}")
      end

      def html_escape(value)
        value.to_s.gsub("&", "&amp;").gsub("<", "&lt;")
          .gsub(">", "&gt;").gsub('"', "&quot;")
      end

      # Format an edge
      def format_edge(edge)
        lines = []

        return lines if !edge.sources || edge.sources.empty? ||
          !edge.targets || edge.targets.empty?

        # Get source and target
        # Build edge attributes
        attrs = build_edge_attributes(edge)
        source = resolved_endpoint(edge.sources.first)
        target = resolved_endpoint(edge.targets.first)
        source_id = edge_endpoint(source)
        target_id = edge_endpoint(target)
        add_cluster_attributes(attrs, source, target)

        # Edge operator
        op = @options[:directed] ? "->" : "--"

        lines << indent("#{source_id} #{op} #{target_id} #{format_attrs(attrs)}")

        lines
      end

      # Build edge attribute hash
      def build_edge_attributes(edge)
        attrs = {}

        # Label
        if edge.labels && !edge.labels.empty?
          attrs[:label] = edge.labels.map(&:text)
        end

        # Edge routing points
        if neato? && edge.sections && !edge.sections.empty?
          section = edge.sections.first
          points = []

          points << section.start_point if section.start_point
          points.concat(section.bend_points) if section.bend_points
          points << section.end_point if section.end_point

          if points.length > 2
            # Build spline path for DOT
            pos_str = points.map do |p|
              "#{p.x.round(2)},#{p.y.round(2)}"
            end.join(" ")
            attrs[:pos] = pos_str
          end
        end

        attrs
      end

      # Format attribute hash to DOT syntax
      def format_attrs(attrs)
        return "" if attrs.empty?

        attr_strs = attrs.map do |key, value|
          rendered = if key == :label && value.is_a?(Array)
                       quote_labels(value)
                     else
                       quote_value(value)
                     end
          "#{key}=#{rendered}"
        end

        "[#{attr_strs.join(', ')}]"
      end

      # Quote a value appropriately for DOT
      def quote_value(value)
        return value.text if value.is_a?(HtmlValue)

        value_str = value.to_s

        return value_str if bare_id?(value_str)

        quote_string(value_str)
      end

      def quote_id(id)
        text = id.to_s
        bare_id?(text) ? text : quote_string(text)
      end

      def bare_id?(text)
        identifier = text.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
        numeral = text.match?(/\A-?(?:\.\d+|\d+(?:\.\d*)?)\z/)
        (identifier || numeral) && !dot_keyword?(text)
      end

      def dot_keyword?(text)
        %w[node edge graph digraph subgraph strict].include?(text.downcase)
      end

      def quote_string(text)
        escaped = text.gsub(/[\\"]/) do |char|
          char == "\\" ? "\\\\" : '\\"'
        end
        "\"#{escaped}\""
      end

      def quote_labels(labels)
        escaped = labels.map do |label|
          label.to_s.gsub(/[\\"]/) do |char|
            char == "\\" ? "\\\\" : '\\"'
          end
        end
        "\"#{escaped.join('\\n')}\""
      end

      def resolved_endpoint(id)
        endpoint_entry(id.to_s) || { type: :node, id: id.to_s, clusters: [] }
      end

      def edge_endpoint(endpoint)
        if endpoint.fetch(:type) == :port
          return "#{quote_id(endpoint[:owner])}:#{endpoint[:port]}"
        end

        if endpoint.fetch(:type) == :compound
          return quote_id(endpoint[:representative])
        end

        quote_id(endpoint[:id])
      end

      def add_cluster_attributes(attrs, source, target)
        source_cluster = source[:cluster]
        target_cluster = target[:cluster]
        if source_cluster && !target.fetch(:clusters).include?(source_cluster)
          attrs[:ltail] = source_cluster
        end
        if target_cluster && !source.fetch(:clusters).include?(target_cluster)
          attrs[:lhead] = target_cluster
        end
      end

      def index_endpoints(graph)
        @endpoint_scopes = {}.compare_by_identity
        @clusters = {}.compare_by_identity
        nodes = descendant_nodes(graph)
        index_node_names(nodes)
        index_clusters(nodes)
        index_cluster_memberships(graph)
        index_all_ports(nodes)
        index_container(graph)
      end

      def index_cluster_memberships(graph)
        @cluster_memberships = {}.compare_by_identity
        index_child_memberships(Array(graph.children), [])
      end

      def index_child_memberships(children, clusters)
        children.each do |node|
          own_clusters = node.hierarchical? ? [*clusters, @clusters.fetch(node)] : clusters
          @cluster_memberships[node] = own_clusters
          index_child_memberships(Array(node.children), own_clusters)
        end
      end

      def index_container(container)
        children = Array(container.children)
        @endpoint_scopes[container] = build_endpoint_scope(children)
        children.each { |node| index_container(node) }
      end

      def descendant_nodes(container)
        Array(container.children).flat_map do |node|
          [node, *descendant_nodes(node)]
        end
      end

      def index_node_names(nodes)
        @node_names = {}.compare_by_identity
        reserved = nodes.to_h { |node| [node.id.to_s, true] }
        used = {}
        nodes.each do |node|
          name = node.id.to_s
          name = available_node_name(name, reserved, used) if used.key?(name)
          @node_names[node] = name
          used[name] = true
        end
      end

      def available_node_name(base, reserved, used)
        index = 2
        loop do
          candidate = "#{base}_#{index}"
          return candidate unless reserved.key?(candidate) || used.key?(candidate)

          index += 1
        end
      end

      def index_clusters(nodes)
        nodes.select(&:hierarchical?).each_with_index do |node, index|
          @clusters[node] = "cluster_#{index}"
        end
      end

      def index_all_ports(nodes)
        @port_names = {}.compare_by_identity
        @declared_ports = {}.compare_by_identity
        ports_by_owner = {}.compare_by_identity
        nodes.each do |node|
          owner = port_representative(node)
          next unless owner

          Array(node.ports).each do |port|
            (ports_by_owner[owner] ||= []) << [node, port]
          end
        end
        ports_by_owner.each { |owner, entries| index_owner_ports(owner, entries) }
      end

      def index_owner_ports(owner, entries)
        reserved = entries.filter_map do |_node, port|
          port_id = port.id.to_s
          port_id if bare_id?(port_id)
        end.to_h { |port_id| [port_id, true] }
        used = {}
        @declared_ports[owner] = entries.filter_map.with_index do |(node, port), index|
          names = (@port_names[node] ||= {})
          port_id = port.id.to_s
          next if names.key?(port_id)

          name = if bare_id?(port_id) && !used.key?(port_id)
                   port_id
                 else
                   available_port_name(index, reserved.merge(used))
                 end
          names[port_id] = name
          used[name] = true
          [port.id, name]
        end
      end

      def available_port_name(index, used)
        loop do
          candidate = "port#{index}"
          return candidate unless used.key?(candidate)

          index += 1
        end
      end

      def build_endpoint_scope(children)
        scope = children.each_with_object({}) do |node, entries|
          entries[node.id.to_s] ||= node_endpoint(node)
        end

        children.each do |node|
          add_ports_to_scope(scope, node)
        end
        add_descendant_scopes(scope, children)

        scope
      end

      def add_descendant_scopes(scope, children)
        children.each { |node| add_descendants_to_scope(scope, node) }
      end

      def add_descendants_to_scope(scope, node)
        Array(node.children).each do |descendant|
          scope[descendant.id.to_s] ||= node_endpoint(descendant)
          add_ports_to_scope(scope, descendant)
          add_descendants_to_scope(scope, descendant)
        end
      end

      def add_ports_to_scope(scope, node)
        owner = port_representative(node)
        return unless owner

        Array(node.ports).each do |port|
          scope[port.id.to_s] ||= port_endpoint(node, owner, port)
        end
      end

      def port_endpoint(node, owner, port)
        {
          type: :port, owner: @node_names.fetch(owner),
          port: @port_names.fetch(node).fetch(port.id.to_s),
          cluster: @clusters[node], clusters: @cluster_memberships.fetch(owner)
        }
      end

      def node_endpoint(node)
        unless node.hierarchical?
          return {
            type: :node, id: @node_names.fetch(node),
            clusters: @cluster_memberships.fetch(node)
          }
        end

        representative = representative_node(node)

        {
          type: :compound, id: @node_names.fetch(node),
          cluster: @clusters.fetch(node),
          representative: @node_names.fetch(representative),
          clusters: @cluster_memberships.fetch(representative)
        }
      end

      def endpoint_entry(id)
        @scope_stack.reverse_each do |scope|
          return scope[id] if scope.key?(id)
        end
        nil
      end

      def with_endpoint_scope(container)
        @scope_stack << @endpoint_scopes.fetch(container)
        yield
      ensure
        @scope_stack.pop
      end

      def port_representative(node)
        node.hierarchical? ? representative_node(node) : node
      end

      def representative_node(node)
        Array(node.children).each do |child|
          return child unless child.hierarchical?

          representative = representative_node(child)
          return representative if representative
        end
        nil
      end

      def declared_ports(node)
        @declared_ports.fetch(node, [])
      end

      def option_resolver
        @option_resolver ||= Elkrb::Options::Resolver.new
      end

      def neato?
        @options[:engine].to_s == "neato"
      end

      # Convert ELK direction to DOT rankdir
      def elk_direction_to_rankdir(direction)
        case direction.to_s.upcase
        when "DOWN"
          "TB"
        when "UP"
          "BT"
        when "RIGHT"
          "LR"
        when "LEFT"
          "RL"
        else
          "TB" # Default
        end
      end

      # Add indentation to a line
      def indent(line)
        (" " * (@indent_level * INDENT_WIDTH)) + line
      end
    end
  end
end
