# frozen_string_literal: true

require "json"

# Builders for the constraint layout specs. They take arguments, so they live
# here rather than as `let` (no arity) or a describe-body `def`.
module ConstraintGraphs
  # A 100x60 node hash, with `constraints` when given.
  def node(id, constraints = nil)
    { id: id, width: 100, height: 60 }.tap do |hash|
      hash[:constraints] = constraints if constraints
    end
  end

  # A node pinned with the layerConstraint option.
  def node_with_layer_kind(id, kind)
    node(id).merge(
      layoutOptions: { "elk.layered.layering.layerConstraint" => kind },
    )
  end

  def edge(id, source, target)
    { id: id, sources: [source], targets: [target] }
  end

  # Runs the graph through Elkrb.layout as parsed JSON.
  def laid_out(graph, algorithm)
    Elkrb.layout(JSON.parse(JSON.generate(graph)), algorithm: algorithm)
  end

  def by_id(result)
    result.children.to_h { |child| [child.id, child] }
  end
end
