# frozen_string_literal: true

# The rows registry_spec probes for one option id: every carrier crossed with
# every spelling the Registry or layout knows for the id, every value shape,
# every algorithm and every input-positioning mode (see .combinations).
# `readers` only says which rows MOVE; a route nobody lists is probed and
# expected not to move, so a route cannot be left out by omission. Which
# carriers an option applies to only decides its status (see .rows).
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

  # @param spellings [Array<String>] from .spellings_for
  # @param readers [Hash{Array => Array, Hash}] [carrier, spelling, shape] =>
  #   algorithms whose output moves, or {positioned => algorithms}; a row
  #   absent from it is expected not to move
  # @param carriers [Array<Symbol>] the carriers the option applies to, such
  #   as the graph's layoutOptions for an option ELK targets at a parent. A
  #   carrier outside it is still probed, and must move exactly as `readers`
  #   records, but its rows do not decide the status.
  # @return [Hash{String => Array}] label => [probe arguments, moves,
  #   algorithm under test, whether the carrier applies]. The probe's own
  #   :algorithm is the root's, which a compound_other row sets to "fixed".
  def rows(spellings:, shapes:, readers:, algorithms:, carriers: CARRIERS)
    check_readers(readers, spellings, shapes.keys, algorithms)
    check_carriers(carriers)

    combinations(spellings, shapes, algorithms)
      .to_h do |carrier, spelling, (shape, values), positioned, name|
      movers = movers(readers[[carrier, spelling, shape]], positioned)
      [[carrier, spelling, shape, "positioned=#{positioned}", name].join(" "),
       [probe_args(carrier, spelling, values, positioned, name),
        movers.include?(name), name, carriers.include?(carrier)]]
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
  # in-scope route moved layout, :accepted when none did, else :partial. A
  # route is in scope when its carrier applies to the option (see .rows) and
  # its algorithm is one the entry declares, or any algorithm in `rows` for a
  # generic entry. A route outside scope is probed by the caller but does not
  # decide the status.
  #
  # @param id [String] canonical Registry id
  # @param rows [Hash{String => Array}] from .rows
  # @param moved [Hash{String => Boolean}] label => whether layout moved
  # @return [Symbol]
  def expected_status(id, rows, moved)
    scope = scope_for(id, rows)
    in_scope = moved.select do |label, _|
      _args, _moves, algorithm, applies = rows.fetch(label)
      applies && scope.include?(algorithm)
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
    probed = rows.values.map { |row| row[2] }.uniq
    declared = Elkrb::Options::Registry.all.fetch(id).fetch(:algorithms)
    return probed if declared == :all

    unknown = declared - probed
    raise ArgumentError, "no row for #{unknown}" unless unknown.empty?

    declared
  end

  # Every carrier x spelling x shape x positioning x algorithm: a reader that
  # acts only for some positionings, or only for some value shapes, shows up
  # as a row that moves.
  def combinations(spellings, shapes, algorithms)
    CARRIERS.product(spellings, shapes.to_a, POSITIONING, algorithms)
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

  # A readers key that matches no generated row (including one with more or
  # fewer than [carrier, spelling, shape]), or names something that is not an
  # algorithm, would otherwise be silently inert.
  def check_readers(readers, spellings, shapes, algorithms)
    readers.each do |route, entry|
      carrier, spelling, shape = route
      known = [CARRIERS.include?(carrier), spellings.include?(spelling),
               shapes.include?(shape)].all?
      raise ArgumentError, "no row for #{route}" unless known && route.size == 3

      check_algorithms(entry, algorithms)
    end
  end

  def check_carriers(carriers)
    unknown = carriers - CARRIERS
    raise ArgumentError, "not carriers: #{unknown}" unless unknown.empty?
    raise ArgumentError, "no carrier applies" if carriers.empty?
  end

  def check_algorithms(entry, algorithms)
    names = entry.is_a?(Hash) ? entry.values.flatten : entry
    unknown = names - algorithms
    raise ArgumentError, "not algorithms: #{unknown}" unless unknown.empty?
  end
end
