# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::HierarchicalProcessor do
  let(:processor_class) do
    Class.new(Elkrb::Layout::Algorithms::BaseAlgorithm) do
      def layout_flat(graph, _options = {})
        # Simple box layout for testing
        return graph if graph.children.nil? || graph.children.empty?

        graph.children.each_with_index do |node, index|
          node.x = index * 100.0
          node.y = 0.0
        end

        apply_padding(graph)
        graph
      end
    end
  end

  let(:processor) { processor_class.new }

  describe "#layout_hierarchical" do
    context "with a flat graph" do
      it "delegates to layout_flat" do
        graph = Elkrb::Graph::Graph.new(
          children: [
            Elkrb::Graph::Node.new(id: "n1", width: 50, height: 50),
            Elkrb::Graph::Node.new(id: "n2", width: 50, height: 50),
          ],
        )

        result = processor.layout_hierarchical(graph)

        expect(result).to be(graph)
        # After layout_flat and apply_padding, nodes are shifted by left padding (12)
        expect(graph.children[0].x).to eq(12.0)
        expect(graph.children[1].x).to eq(112.0)
      end
    end

    context "with a hierarchical graph" do
      it "recursively layouts child nodes" do
        child_node = Elkrb::Graph::Node.new(
          id: "parent",
          width: 100,
          height: 100,
          children: [
            Elkrb::Graph::Node.new(id: "child1", width: 30, height: 30),
            Elkrb::Graph::Node.new(id: "child2", width: 30, height: 30),
          ],
        )

        graph = Elkrb::Graph::Graph.new(
          children: [child_node],
        )

        result = processor.layout_hierarchical(graph)

        expect(result).to be(graph)
        # Children should have positions set
        expect(child_node.children[0].x).not_to be_nil
        expect(child_node.children[1].x).not_to be_nil
      end

      it "applies parent constraints with padding" do
        layout_opts = Elkrb::Graph::LayoutOptions.new
        layout_opts["padding"] = 10

        child_node = Elkrb::Graph::Node.new(
          id: "parent",
          width: 100,
          height: 100,
          children: [
            Elkrb::Graph::Node.new(id: "child1", width: 30, height: 30, x: 0,
                                   y: 0),
          ],
          layout_options: layout_opts,
        )

        graph = Elkrb::Graph::Graph.new(
          children: [child_node],
        )

        processor.layout_hierarchical(graph)

        # Child should be offset by custom padding (10) + outer padding (12 from apply_padding)
        expect(child_node.children[0].x).to be >= 10.0
        expect(child_node.children[0].y).to be >= 10.0
      end

      it "updates parent bounds to contain children" do
        child_node = Elkrb::Graph::Node.new(
          id: "parent",
          width: 0,
          height: 0,
          children: [
            Elkrb::Graph::Node.new(id: "child1", width: 30, height: 30, x: 0,
                                   y: 0),
            Elkrb::Graph::Node.new(id: "child2", width: 30, height: 30, x: 40,
                                   y: 0),
          ],
        )

        graph = Elkrb::Graph::Graph.new(
          children: [child_node],
        )

        processor.layout_hierarchical(graph)

        # Parent should be sized to contain children + padding
        expect(child_node.width).to be > 70 # 70 for children + padding
        expect(child_node.height).to be > 30 # 30 for children + padding
      end
    end
  end

  describe "#apply_parent_constraints" do
    it "adjusts children for padding" do
      layout_opts = Elkrb::Graph::LayoutOptions.new
      layout_opts["padding"] =
        { "left" => 15, "top" => 20, "right" => 10, "bottom" => 10 }

      node = Elkrb::Graph::Node.new(
        id: "parent",
        children: [
          Elkrb::Graph::Node.new(id: "child", x: 0, y: 0),
        ],
        layout_options: layout_opts,
      )

      graph = Elkrb::Graph::Graph.new(children: [node])
      processor.send(:apply_parent_constraints, graph)

      expect(node.children[0].x).to eq(15.0)
      expect(node.children[0].y).to eq(20.0)
    end
  end

  describe "#get_padding" do
    it "returns default padding when no options" do
      node = Elkrb::Graph::Node.new(id: "n1")
      padding = processor.send(:get_padding, node)

      expect(padding).to eq({ top: 12.0, right: 12.0, bottom: 12.0,
                              left: 12.0 })
    end

    it "parses hash padding" do
      layout_opts = Elkrb::Graph::LayoutOptions.new
      layout_opts["padding"] = { "left" => 5, "top" => 10 }

      node = Elkrb::Graph::Node.new(
        id: "n1",
        layout_options: layout_opts,
      )

      padding = processor.send(:get_padding, node)

      expect(padding[:left]).to eq(5.0)
      expect(padding[:top]).to eq(10.0)
      expect(padding[:right]).to eq(12.0) # Default
    end

    it "parses uniform numeric padding" do
      layout_opts = Elkrb::Graph::LayoutOptions.new
      layout_opts["padding"] = 20

      node = Elkrb::Graph::Node.new(
        id: "n1",
        layout_options: layout_opts,
      )

      padding = processor.send(:get_padding, node)

      expect(padding).to eq({ top: 20, right: 20, bottom: 20, left: 20 })
    end
  end

  describe "#calculate_children_bounds" do
    it "calculates bounds for children" do
      node = Elkrb::Graph::Node.new(
        id: "parent",
        children: [
          Elkrb::Graph::Node.new(id: "c1", x: 10, y: 20, width: 30, height: 40),
          Elkrb::Graph::Node.new(id: "c2", x: 50, y: 30, width: 20, height: 30),
        ],
      )

      bounds = processor.send(:calculate_children_bounds, node)

      expect(bounds[:min_x]).to eq(10)
      expect(bounds[:min_y]).to eq(20)
      expect(bounds[:width]).to eq(60) # 10 to 70 (50+20)
      expect(bounds[:height]).to eq(40) # 20 to 60 (30+30)
    end

    it "returns zero bounds for no children" do
      node = Elkrb::Graph::Node.new(id: "parent")

      bounds = processor.send(:calculate_children_bounds, node)

      expect(bounds).to eq({ min_x: 0, min_y: 0, width: 0, height: 0 })
    end
  end

  describe "#handle_cross_hierarchy_edges" do
    it "handles edges crossing hierarchy levels" do
      parent1 = Elkrb::Graph::Node.new(
        id: "p1",
        children: [
          Elkrb::Graph::Node.new(id: "c1", x: 0, y: 0, width: 30, height: 30),
        ],
      )

      parent2 = Elkrb::Graph::Node.new(id: "p2", x: 100, y: 0, width: 50,
                                       height: 50)

      edge = Elkrb::Graph::Edge.new(
        sources: ["c1"],
        targets: ["p2"],
        sections: [
          Elkrb::Graph::EdgeSection.new(
            start_point: Elkrb::Geometry::Point.new(x: 15, y: 15),
            end_point: Elkrb::Geometry::Point.new(x: 125, y: 25),
          ),
        ],
      )

      graph = Elkrb::Graph::Graph.new(
        children: [parent1, parent2],
        edges: [edge],
      )

      processor.send(:handle_cross_hierarchy_edges, graph)

      # Edge should have bend points added
      section = edge.sections.first
      expect(section.bend_points).not_to be_empty
    end
  end

  describe "integration with BaseAlgorithm" do
    it "automatically uses hierarchical layout for hierarchical graphs" do
      child_node = Elkrb::Graph::Node.new(
        id: "parent",
        width: 100,
        height: 100,
        children: [
          Elkrb::Graph::Node.new(id: "child1", width: 30, height: 30),
          Elkrb::Graph::Node.new(id: "child2", width: 30, height: 30),
        ],
      )

      graph = Elkrb::Graph::Graph.new(
        children: [child_node],
      )

      processor.layout(graph)

      # Should have laid out children
      expect(child_node.children[0].x).not_to be_nil
      expect(child_node.children[1].x).not_to be_nil

      # Parent should be sized appropriately
      expect(child_node.width).to be > 0
      expect(child_node.height).to be > 0
    end
  end
end
