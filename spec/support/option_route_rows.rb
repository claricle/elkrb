# frozen_string_literal: true

# The rows registry_spec probes for one option id: every carrier crossed with
# every spelling the Registry or layout knows for the id, every value shape,
# every algorithm and the input-positioning modes (see .combinations).
# `readers` only says which rows MOVE; a route nobody lists is probed and
# expected not to move, so a route cannot be left out by omission.
module OptionRouteRows
  module_function

  # How an option reaches layout: a call option under a String or a Symbol
  # key, the graph's layoutOptions, an edge's layoutOptions, or a compound
  # node's layoutOptions (the compound sets a different elk.algorithm under a
  # root laid out by "fixed", sets the root's own, or sets none).
  CARRIER_ARGS = {
    call_string: ->(_spelling, _name) { { route: :call_option } },
    call_symbol: lambda { |spelling, _name|
      { route: :call_option, key: spelling.to_sym }
    },
    root: ->(_spelling, _name) { { route: :layout_options } },
    edge: ->(_spelling, _name) { { route: :edge_layout_options } },
    compound_none: ->(_spelling, _name) { { route: :compound_layout_options } },
    compound_same: lambda { |_spelling, name|
      { route: :compound_layout_options,
        compound_options: { "elk.algorithm" => name } }
    },
    compound_other: lambda { |_spelling, name|
      { route: :compound_layout_options, algorithm: "fixed",
        compound_options: { "elk.algorithm" => name } }
    },
  }.freeze
  CARRIERS = CARRIER_ARGS.keys.freeze

  # Whether the nodes arrive with input positions: all, none, or the first
  # node only.
  POSITIONING = [true, false, :some].freeze

  # @param id [String] canonical Registry id
  # @param internal [String] the name layout reads, when it is not an alias
  # @return [Array<String>] the id, its org.eclipse.elk. long form, every
  #   alias the Registry maps to it, and the internal name
  def spellings_for(id, internal)
    aliases = Elkrb::Options::Registry.all.fetch(id).fetch(:aliases, [])
    ([id, "org.eclipse.#{id}"] + aliases + [internal]).uniq
  end

  # @param readers [Hash{Array => Array, Hash}] [carrier, spelling, shape] =>
  #   algorithms whose output moves, or {positioned => algorithms}; a row
  #   absent from it is expected not to move
  # @return [Hash{String => Array}] label => [probe arguments, moves,
  #   algorithm under test]. The probe's own :algorithm is the root's, which
  #   a compound_other row sets to "fixed".
  def rows(id:, internal:, shapes:, readers:, algorithms:)
    spellings = spellings_for(id, internal)
    check_readers(readers, spellings, shapes.keys, algorithms)

    combinations = combinations(spellings, shapes, algorithms)
    combinations.to_h do |carrier, spelling, (shape, values), positioned, name|
      movers = movers(readers[[carrier, spelling, shape]], positioned)
      [[carrier, spelling, shape, "positioned=#{positioned}", name].join(" "),
       [probe_args(carrier, spelling, values, positioned, name),
        movers.include?(name), name]]
    end
  end

  # @param readers [Array<String>] algorithms that move in every mode
  # @param unpositioned [Array<String>] algorithms that move when no node has
  #   an input position
  # @param first_only [Array<String>] algorithms that move when only the
  #   first node has one
  def by_positioning(readers, unpositioned: readers, first_only: unpositioned)
    { true => readers, false => unpositioned, some: first_only }
  end

  # The status the Registry should report for `id`: :honoured when every
  # in-scope route moved layout, :accepted when none did, else :partial. Scope
  # is the entry's declared algorithms, or every algorithm in `rows` for a
  # generic entry. A route outside it is probed by the caller but does not
  # decide the status.
  #
  # @param id [String] canonical Registry id
  # @param rows [Hash{String => Array}] from .rows
  # @param moved [Hash{String => Boolean}] label => whether layout moved
  # @return [Symbol]
  def expected_status(id, rows, moved)
    scope = scope_for(id, rows)
    in_scope = moved.select do |label, _|
      scope.include?(rows.fetch(label).last)
    end.values
    raise ArgumentError, "no row in scope #{scope}" if in_scope.empty?

    if in_scope.all? then :honoured
    elsif in_scope.none? then :accepted
    else :partial
    end
  end

  # @return [Array<String>] the Registry entry's declared algorithms, or every
  #   algorithm in `rows` for a generic entry
  # @raise [ArgumentError] when a declared algorithm has no row
  def scope_for(id, rows)
    probed = rows.values.map(&:last).uniq
    declared = Elkrb::Options::Registry.all.fetch(id).fetch(:algorithms)
    return probed if declared == :all

    unknown = declared - probed
    raise ArgumentError, "no row for #{unknown}" unless unknown.empty?

    declared
  end

  # The first shape is probed at every positioning; the others at
  # positioned=true only, which keeps every carrier x spelling x shape x
  # algorithm route and bounds the run time. A reader of a later shape that
  # acts only without input positions is not seen.
  def combinations(spellings, shapes, algorithms)
    shapes.each_with_index.flat_map do |shape, index|
      positionings = index.zero? ? POSITIONING : [true]
      CARRIERS.product(spellings, [shape], positionings, algorithms)
    end
  end

  def movers(entry, positioned)
    return [] unless entry

    entry.is_a?(Hash) ? entry.fetch(positioned) : entry
  end

  def probe_args(carrier, spelling, values, positioned, name)
    args = { algorithm: name, key: spelling, values: values,
             positioned: positioned }
    args.merge(CARRIER_ARGS.fetch(carrier).call(spelling, name))
  end

  # A readers key that matches no generated row, or names something that is
  # not an algorithm, would otherwise be silently inert.
  def check_readers(readers, spellings, shapes, algorithms)
    readers.each do |route, entry|
      carrier, spelling, shape = route
      unless [CARRIERS.include?(carrier), spellings.include?(spelling),
              shapes.include?(shape)].all?
        raise ArgumentError, "no row for #{route}"
      end

      check_algorithms(entry, algorithms)
    end
  end

  def check_algorithms(entry, algorithms)
    names = entry.is_a?(Hash) ? entry.values.flatten : entry
    unknown = names - algorithms
    raise ArgumentError, "not algorithms: #{unknown}" unless unknown.empty?
  end
end
