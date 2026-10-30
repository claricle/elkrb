# frozen_string_literal: true

require "spec_helper"

# `elk.alignment` places a node across its layer. ELK names the side in the
# picture: LEFT/RIGHT in a horizontal layout, TOP/BOTTOM in a vertical one,
# CENTER in either; AUTOMATIC (the default) leans a node by its ports. The
# nodes share one layer because components are not separated.
RSpec.describe "elk.alignment in the layered algorithm" do
  def laid_out(direction, alignment, sizes)
    children = sizes.each_with_index.map do |(width, height), index|
      node = { id: "n#{index}", width: width, height: height }
      next node unless alignment

      node.merge(layoutOptions: { "elk.alignment" => alignment })
    end
    Elkrb.layout(flat_graph(direction, children)).children
  end

  def flat_graph(direction, children)
    { id: "root", children: children, edges: [],
      layoutOptions: { "elk.direction" => direction,
                       "elk.separateConnectedComponents" => false,
                       "elk.padding" => "[top=0,left=0,bottom=0,right=0]" } }
  end

  # One layer of unconnected nodes: widths 100/40/100/100, heights 80/300/80/80.
  let(:wide_tall) { [[100, 80], [100, 300], [100, 80], [100, 80]] }
  let(:narrow) { [[100, 80], [40, 80], [100, 80]] }

  it "centres unequal nodes across a DOWN layer by default" do
    expect(laid_out("DOWN", nil, wide_tall).map(&:y))
      .to eq([110.0, 0.0, 110.0, 110.0])
  end

  it "top-aligns a DOWN layer with TOP" do
    expect(laid_out("DOWN", "TOP", wide_tall).map(&:y)).to all(eq(0.0))
  end

  it "bottom-aligns a DOWN layer with BOTTOM" do
    nodes = laid_out("DOWN", "BOTTOM", wide_tall)
    expect(nodes.map { |node| node.y + node.height }).to all(eq(300.0))
  end

  it "starts a RIGHT layer at its left with LEFT" do
    expect(laid_out("RIGHT", "LEFT", narrow).map(&:x)).to all(eq(0.0))
  end

  it "ends a RIGHT layer at its right with RIGHT" do
    nodes = laid_out("RIGHT", "RIGHT", narrow)
    expect(nodes.map { |node| node.x + node.width }).to all(eq(100.0))
  end

  it "keeps a mirrored LEFT layer at the left of the picture with LEFT" do
    nodes = laid_out("LEFT", "LEFT", narrow)
    expect(nodes.map(&:x).uniq.size).to eq(1)
  end

  it "keeps a mirrored UP layer at the top of the picture with TOP" do
    nodes = laid_out("UP", "TOP", wide_tall)
    expect(nodes.map(&:y)).to all(eq(0.0))
  end

  it "centres with CENTER in a horizontal layout" do
    expect(laid_out("RIGHT", "CENTER", narrow).map(&:x))
      .to eq([0.0, 30.0, 0.0])
  end

  it "treats a side across the layers as AUTOMATIC" do
    expect(laid_out("DOWN", "LEFT", wide_tall).map(&:y))
      .to eq(laid_out("DOWN", nil, wide_tall).map(&:y))
  end

  it "reads the alignment of each node" do
    children = [{ id: "a", width: 10, height: 10,
                  layoutOptions: { "elk.alignment" => "TOP" } },
                { id: "b", width: 10, height: 50 }]
    expect(Elkrb.layout(flat_graph("DOWN", children)).children.map(&:y))
      .to eq([0.0, 0.0])
  end
end
