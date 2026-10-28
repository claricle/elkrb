# frozen_string_literal: true

require_relative "have_labels_inside_owner"

RSpec.describe "have_labels_inside_owner" do
  def graph_with_label(placement, label_x, label_y)
    label = Elkrb::Graph::Label.new(text: "L", width: 20, height: 10,
                                    x: label_x, y: label_y)
    options = placement ? { "elk.nodeLabels.placement" => placement } : nil
    node = Elkrb::Graph::Node.new(id: "n", x: 30, y: 30, width: 100,
                                  height: 60, labels: [label],
                                  layout_options: options)
    Elkrb::Graph::Graph.new(id: "root", children: [node])
  end

  it "passes an INSIDE label within the owner's box" do
    expect(graph_with_label("INSIDE V_TOP H_LEFT", 5, 5))
      .to have_labels_inside_owner
  end

  {
    "left" => [-1, 5],
    "top" => [5, -1],
    "right" => [81, 5],
    "bottom" => [5, 51],
  }.each do |edge, (x, y)|
    it "fails an INSIDE label past the owner's #{edge} edge" do
      expect(graph_with_label("[INSIDE]", x, y))
        .not_to have_labels_inside_owner
    end
  end

  it "ignores an OUTSIDE label" do
    expect(graph_with_label("OUTSIDE V_TOP H_CENTER", 40, -15))
      .to have_labels_inside_owner
  end

  it "ignores a label with no placement option" do
    expect(graph_with_label(nil, 500, 500)).to have_labels_inside_owner
  end
end
