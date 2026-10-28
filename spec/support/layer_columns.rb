# frozen_string_literal: true

# Lays out a graph of 40x30 nodes with the layered algorithm and answers
# the node ids of each layer, top to bottom, left to right.
module LayerColumns
  def layer_columns(ids:, edges:, options: {})
    graph = Elkrb::Graph::Graph.from_json(
      JSON.generate(layer_graph(ids, edges, options)),
    )

    Elkrb.layout(graph, algorithm: "layered").children.group_by(&:x)
      .sort.map { |_, nodes| nodes.sort_by(&:y).map(&:id) }
  end

  def layer_graph(ids, edges, options)
    {
      "id" => "root",
      "layoutOptions" => { "elk.algorithm" => "layered" }.merge(options),
      "children" => ids.map do |id|
        { "id" => id, "width" => 40, "height" => 30 }
      end,
      "edges" => edges.map do |source, target|
        { "id" => "#{source}-#{target}", "sources" => [source],
          "targets" => [target] }
      end,
    }
  end
end

RSpec.configure { |config| config.include LayerColumns }
