# frozen_string_literal: true

# Builds the graphs of spec/fixtures/spore_compaction/elkjs_cases.json, whose
# expected positions were produced by elkjs 0.11.0 laying out the same input.
module SporeCompactionGraphs
  FIXTURE = File.expand_path("../fixtures/spore_compaction/elkjs_cases.json", __dir__)

  def spore_compaction_cases
    JSON.parse(File.read(FIXTURE))
  end

  # A fresh Graph for one fixture case, laid out by sporeCompaction.
  def spore_compaction_graph(kase)
    options = { "elk.algorithm" => "sporeCompaction" }
    Elkrb::Graph::Graph.from_hash(
      "id" => "root",
      "layoutOptions" => options.merge(kase.fetch("options")),
      "children" => Marshal.load(Marshal.dump(kase.fetch("children"))),
      "edges" => [],
    )
  end
end
