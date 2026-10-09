# frozen_string_literal: true

# Builds a JSON-shaped graph of `size` nodes joined in one chain.
module ChainGraph
  def chain_graph(size)
    nodes = Array.new(size) do |i|
      { "id" => "n#{i}", "width" => 30, "height" => 20 }
    end
    edges = (1...size).map do |i|
      { "id" => "e#{i}", "sources" => ["n#{i - 1}"], "targets" => ["n#{i}"] }
    end
    JSON.parse(
      JSON.generate("id" => "root", "children" => nodes, "edges" => edges),
    )
  end
end

RSpec.configure { |config| config.include ChainGraph }
