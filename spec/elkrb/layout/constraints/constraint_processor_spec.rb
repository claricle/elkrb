# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Constraints::ConstraintProcessor do
  let(:processor) { described_class.new }

  describe "#has_constraints?" do
    it "returns false for graph without constraints" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      node = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60)
      graph.children = [node]

      expect(processor.has_constraints?(graph)).to be false
    end

    it "returns true for graph with node constraints" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      node = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60)
      node.constraints = Elkrb::Graph::NodeConstraints.new(fixed_position: true)
      graph.children = [node]

      expect(processor.has_constraints?(graph)).to be true
    end

    it "checks nested constraints only in their own level" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      parent = Elkrb::Graph::Node.new(id: "parent", width: 200, height: 150)
      child = Elkrb::Graph::Node.new(id: "child", width: 50, height: 30)
      child.constraints = Elkrb::Graph::NodeConstraints.new(layer: 1)
      parent.children = [child]
      graph.children = [parent]

      child_level = Elkrb::Graph::Graph.new(children: parent.children)

      expect(processor.has_constraints?(graph)).to be false
      expect(processor.has_constraints?(child_level)).to be true
    end
  end

  describe "#apply_all" do
    it "returns graph unchanged if no constraints" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      node = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60, x: 50,
                                    y: 100)
      graph.children = [node]

      result = processor.apply_all(graph)

      expect(result).to eq(graph)
      expect(node.x).to eq(50)
      expect(node.y).to eq(100)
    end

    it "applies fixed position constraint" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      node = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60, x: 500,
                                    y: 800)
      node.constraints = Elkrb::Graph::NodeConstraints.new(fixed_position: true)
      graph.children = [node]

      processor.apply_pre_layout(graph)
      node.x = 0
      node.y = 0
      processor.enforce_post_layout(graph)

      expect([node.x, node.y]).to eq([500, 800])
      expect(node.properties).to be_nil
    end

    it "releases a node once fixed_position is cleared" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      node = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60, x: 500,
                                    y: 800)
      node.constraints = Elkrb::Graph::NodeConstraints.new(fixed_position: true)
      graph.children = [node]

      processor.apply_pre_layout(graph)
      node.constraints.fixed_position = false
      node.x = 0
      node.y = 0
      processor.enforce_post_layout(graph)

      expect([node.x, node.y]).to eq([0, 0])
    end

    it "leaves no scratch state in node properties" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      node = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60, x: 5,
                                    y: 8)
      node.constraints = Elkrb::Graph::NodeConstraints.new(fixed_position: true,
                                                           layer: 2)
      graph.children = [node]

      processor.apply_all(graph)

      expect(node.properties).to be_nil
    end

    it "applies alignment constraint" do
      graph = Elkrb::Graph::Graph.new(id: "root")

      node1 = Elkrb::Graph::Node.new(id: "db1", width: 100, height: 60, x: 100,
                                     y: 100)
      node1.constraints = Elkrb::Graph::NodeConstraints.new(
        align_group: "databases",
        align_direction: "horizontal",
      )

      node2 = Elkrb::Graph::Node.new(id: "db2", width: 100, height: 60, x: 300,
                                     y: 150)
      node2.constraints = Elkrb::Graph::NodeConstraints.new(
        align_group: "databases",
        align_direction: "horizontal",
      )

      graph.children = [node1, node2]

      processor.apply_all(graph)

      # Should align to average y
      avg_y = (100 + 150) / 2.0
      expect(node1.y).to eq(avg_y)
      expect(node2.y).to eq(avg_y)
    end

    it "applies relative position constraint" do
      graph = Elkrb::Graph::Graph.new(id: "root")

      ref_node = Elkrb::Graph::Node.new(id: "backend", width: 100, height: 60,
                                        x: 200, y: 300)

      offset = Elkrb::Graph::RelativeOffset.new(x: 150, y: 0)
      api_node = Elkrb::Graph::Node.new(id: "api", width: 100, height: 60)
      api_node.constraints = Elkrb::Graph::NodeConstraints.new(
        relative_to: "backend",
        relative_offset: offset,
      )

      graph.children = [ref_node, api_node]

      processor.apply_all(graph)

      expect(api_node.x).to eq(350)  # 200 + 150
      expect(api_node.y).to eq(300)  # 300 + 0
    end

    it "applies multiple constraint types" do
      graph = Elkrb::Graph::Graph.new(id: "root")

      # Fixed position node
      fixed_node = Elkrb::Graph::Node.new(id: "gateway", width: 100,
                                          height: 60, x: 500, y: 100)
      fixed_node.constraints = Elkrb::Graph::NodeConstraints.new(fixed_position: true)

      # Aligned nodes
      db1 = Elkrb::Graph::Node.new(id: "db1", width: 100, height: 60, x: 100,
                                   y: 400)
      db1.constraints = Elkrb::Graph::NodeConstraints.new(
        align_group: "databases",
        align_direction: "horizontal",
        layer: 2,
      )

      db2 = Elkrb::Graph::Node.new(id: "db2", width: 100, height: 60, x: 300,
                                   y: 450)
      db2.constraints = Elkrb::Graph::NodeConstraints.new(
        align_group: "databases",
        align_direction: "horizontal",
        layer: 2,
      )

      graph.children = [fixed_node, db1, db2]

      processor.apply_all(graph)

      expect([fixed_node.x, fixed_node.y]).to eq([500, 100])
      expect(db1.y).to eq(db2.y)
      expect([db1, db2, fixed_node].map(&:properties)).to all(be_nil)
    end
  end

  describe "#validate_all" do
    it "returns empty array if no constraints" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      node = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60, x: 50,
                                    y: 100)
      graph.children = [node]

      errors = processor.validate_all(graph)

      expect(errors).to be_empty
    end

    it "validates fixed position constraint" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      node = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60, x: 500,
                                    y: 800)
      node.constraints = Elkrb::Graph::NodeConstraints.new(fixed_position: true)
      graph.children = [node]
      processor.apply_pre_layout(graph)

      errors = processor.validate_all(graph)

      expect(errors).to be_empty
    end

    it "detects fixed position violation" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      node = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60, x: 500,
                                    y: 800)
      node.constraints = Elkrb::Graph::NodeConstraints.new(fixed_position: true)
      graph.children = [node]
      processor.apply_pre_layout(graph)
      node.x = 600
      node.y = 900

      errors = processor.validate_all(graph)

      expect(errors).not_to be_empty
      expect(errors.first).to include("fixed_position constraint")
      expect(errors.first).to include("was moved")
    end

    it "validates alignment constraint" do
      graph = Elkrb::Graph::Graph.new(id: "root")

      node1 = Elkrb::Graph::Node.new(id: "db1", width: 100, height: 60, x: 100,
                                     y: 400)
      node1.constraints = Elkrb::Graph::NodeConstraints.new(
        align_group: "databases",
        align_direction: "horizontal",
      )

      node2 = Elkrb::Graph::Node.new(id: "db2", width: 100, height: 60, x: 300,
                                     y: 400)
      node2.constraints = Elkrb::Graph::NodeConstraints.new(
        align_group: "databases",
        align_direction: "horizontal",
      )

      graph.children = [node1, node2]

      errors = processor.validate_all(graph)

      expect(errors).to be_empty
    end

    it "detects alignment violation" do
      graph = Elkrb::Graph::Graph.new(id: "root")

      node1 = Elkrb::Graph::Node.new(id: "db1", width: 100, height: 60, x: 100,
                                     y: 400)
      node1.constraints = Elkrb::Graph::NodeConstraints.new(
        align_group: "databases",
        align_direction: "horizontal",
      )

      node2 = Elkrb::Graph::Node.new(id: "db2", width: 100, height: 60, x: 300,
                                     y: 500)
      node2.constraints = Elkrb::Graph::NodeConstraints.new(
        align_group: "databases",
        align_direction: "horizontal",
      )

      graph.children = [node1, node2]

      errors = processor.validate_all(graph)

      expect(errors).not_to be_empty
      expect(errors.first).to include("databases")
      expect(errors.first).to include("different y coordinates")
    end

    it "validates relative position constraint" do
      graph = Elkrb::Graph::Graph.new(id: "root")

      ref_node = Elkrb::Graph::Node.new(id: "backend", width: 100, height: 60,
                                        x: 200, y: 300)

      offset = Elkrb::Graph::RelativeOffset.new(x: 150, y: 0)
      api_node = Elkrb::Graph::Node.new(id: "api", width: 100, height: 60,
                                        x: 350, y: 300)
      api_node.constraints = Elkrb::Graph::NodeConstraints.new(
        relative_to: "backend",
        relative_offset: offset,
      )

      graph.children = [ref_node, api_node]

      errors = processor.validate_all(graph)

      expect(errors).to be_empty
    end

    it "reports, rather than raises, on a graph with no coordinates" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      ref = Elkrb::Graph::Node.new(id: "ref", width: 100, height: 60)
      node = Elkrb::Graph::Node.new(id: "api", width: 100, height: 60)
      node.constraints = Elkrb::Graph::NodeConstraints.new(
        relative_to: "ref",
        relative_offset: Elkrb::Graph::RelativeOffset.new(x: 150, y: 0),
      )
      graph.children = [ref, node]

      expect { processor.apply_all(graph) }.not_to raise_error
      errors = processor.validate_all(graph)

      expect(errors).to contain_exactly(a_string_including("no coordinates"))
    end

    it "reports a relative_to cycle once per node and does not move it" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      offset = Elkrb::Graph::RelativeOffset.new(x: 10, y: 0)
      a, b = [%w[a b], %w[b a]].map do |id, ref|
        Elkrb::Graph::Node.new(
          id: id, width: 10, height: 10, x: 1, y: 2,
          constraints: Elkrb::Graph::NodeConstraints.new(relative_to: ref,
                                                         relative_offset: offset)
        )
      end
      graph.children = [a, b]

      processor.apply_all(graph)

      expect([a.x, b.x]).to eq([1, 1])
      expect(processor.validate_all(graph).length).to eq(2)
    end

    it "detects missing reference node" do
      graph = Elkrb::Graph::Graph.new(id: "root")

      offset = Elkrb::Graph::RelativeOffset.new(x: 150, y: 0)
      api_node = Elkrb::Graph::Node.new(id: "api", width: 100, height: 60)
      api_node.constraints = Elkrb::Graph::NodeConstraints.new(
        relative_to: "nonexistent",
        relative_offset: offset,
      )

      graph.children = [api_node]

      errors = processor.validate_all(graph)

      expect(errors).not_to be_empty
      expect(errors.first).to include("nonexistent")
      expect(errors.first).to include("doesn't exist")
    end
  end

  describe "integration with layout" do
    it "works with layered algorithm" do
      graph = Elkrb::Graph::Graph.new(id: "root")

      # Fixed position node
      n1 = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60, x: 500,
                                  y: 100)
      n1.constraints = Elkrb::Graph::NodeConstraints.new(fixed_position: true)

      # Normal nodes
      n2 = Elkrb::Graph::Node.new(id: "n2", width: 100, height: 60)
      n3 = Elkrb::Graph::Node.new(id: "n3", width: 100, height: 60)

      graph.children = [n1, n2, n3]
      graph.edges = [
        Elkrb::Graph::Edge.new(id: "e1", sources: ["n1"], targets: ["n2"]),
        Elkrb::Graph::Edge.new(id: "e2", sources: ["n2"], targets: ["n3"]),
      ]

      result = Elkrb.layout(graph, algorithm: "layered")

      # Fixed node should not have moved
      expect(result.children[0].x).to eq(500)
      expect(result.children[0].y).to eq(100)
    end

    it "works with force algorithm" do
      graph = Elkrb::Graph::Graph.new(id: "root")

      # Aligned nodes
      n1 = Elkrb::Graph::Node.new(id: "db1", width: 100, height: 60)
      n1.constraints = Elkrb::Graph::NodeConstraints.new(
        align_group: "databases",
        align_direction: "horizontal",
      )

      n2 = Elkrb::Graph::Node.new(id: "db2", width: 100, height: 60)
      n2.constraints = Elkrb::Graph::NodeConstraints.new(
        align_group: "databases",
        align_direction: "horizontal",
      )

      graph.children = [n1, n2]

      result = Elkrb.layout(graph, algorithm: "force")

      # Nodes should be aligned horizontally (same y)
      expect(result.children[0].y).to eq(result.children[1].y)
    end
  end
end
