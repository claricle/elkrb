# frozen_string_literal: true

require "spec_helper"

# Every way a key can be written, in every kind of option map, in every
# order. One table, so a new shape is a new row and the rule is stated once:
# the best spelling wins, a String beats a Symbol of the same spelling, a Hash
# default is never a value, and where the key was asked for changes nothing.
RSpec.describe Elkrb::Options::Resolver, "key shapes" do
  id = "elk.spacing.nodeNode"
  # Best spelling first: the id, its org.eclipse.elk. form, then the aliases.
  spellings = [
    id,
    "org.eclipse.elk.spacing.nodeNode",
    *Elkrb::Options::Registry.all.fetch(id).fetch(:aliases),
  ]
  key_forms = {
    "String" => :to_s.to_proc,
    "Symbol" => :to_sym.to_proc,
  }
  map_kinds = %i[plain default default_proc]
  orders = %i[best_first best_last]
  # Highest rank first, the order the card gives.
  sources = %i[layout_options nested properties call]
  other = "custom.other"
  nested_keys = { "String" => "properties", "Symbol" => :properties }

  describe "one spelling alone" do
    sources.each do |source|
      spellings.each do |spelling|
        key_forms.each do |form, convert|
          map_kinds.each do |kind|
            it "reads #{form} #{spelling} in #{source} on a #{kind} map " \
               "for every way of asking" do
              resolver, elements = option_source(
                source, [[convert.call(spelling), 40]], kind
              )

              answers = answers_for(resolver, elements, spellings)

              expect(answers).to all(eq(40.0))
            end
          end
        end
      end
    end
  end

  describe "two spellings of one id in one map" do
    sources.each do |source|
      map_kinds.each do |kind|
        orders.each do |order|
          spellings.combination(2).to_a.each do |best, worse|
            key_forms.each do |best_form, best_convert|
              key_forms.each do |worse_form, worse_convert|
                it "lets #{best_form} #{best} beat #{worse_form} #{worse} " \
                   "in #{source} on a #{kind} map, #{order}" do
                  pairs = [
                    [best_convert.call(best), 50],
                    [worse_convert.call(worse), 70],
                  ]
                  pairs.reverse! if order == :best_last
                  resolver, elements = option_source(source, pairs, kind)

                  answers = answers_for(resolver, elements, spellings)

                  expect(answers).to all(eq(50.0))
                end
              end
            end
          end
        end
      end
    end
  end

  describe "one spelling as a String and as a Symbol" do
    sources.each do |source|
      map_kinds.each do |kind|
        orders.each do |order|
          spellings.each do |spelling|
            it "lets the String #{spelling} beat the Symbol in #{source} " \
               "on a #{kind} map, #{order}" do
              pairs = [[spelling, 50], [spelling.to_sym, 70]]
              pairs.reverse! if order == :best_last
              resolver, elements = option_source(source, pairs, kind)

              answers = answers_for(resolver, elements, spellings)

              expect(answers).to all(eq(50.0))
            end
          end
        end
      end
    end
  end

  describe "a nil under the best spelling" do
    sources.each do |source|
      map_kinds.each do |kind|
        key_forms.each do |form, convert|
          it "falls through to the next spelling in #{source} on a #{kind} " \
             "map, #{form} keys" do
            pairs = [[convert.call(id), nil],
                     [convert.call(spellings.last), 70]]
            resolver, elements = option_source(source, pairs, kind)

            expect(resolver.get(id, *elements)).to eq(70.0)
          end
        end
      end
    end
  end

  describe "the nested properties map" do
    sources.each do |source|
      next unless source == :nested

      nested_keys.each do |form, nested_key|
        map_kinds.each do |kind|
          it "is read under a #{form} properties key on a #{kind} map" do
            resolver, elements = option_source(
              source, [[id.to_sym, 40]], kind, nested_key
            )

            expect(resolver.get(id, *elements)).to eq(40.0)
          end
        end
      end
    end
  end

  describe "a map that does not name the option" do
    sources.each do |source|
      map_kinds.each do |kind|
        it "answers the registry default, not the Hash default, in #{source} " \
           "on a #{kind} map" do
          resolver, elements = option_source(source, [[other, 1]], kind)

          expect(resolver.get(id, *elements)).to eq(20.0)
        end

        it "answers nil for an unknown key, not the Hash default, in " \
           "#{source} on a #{kind} map" do
          resolver, elements = option_source(source, [[other, 1]], kind)

          answer = resolver.get("custom.thing", *elements, default: nil)

          expect(answer).to be_nil
        end
      end
    end
  end

  describe "the same option in two sources" do
    sources.combination(2).to_a.each do |higher, lower|
      map_kinds.each do |kind|
        key_forms.each do |form, convert|
          it "reads #{higher} before #{lower} on a #{kind} map, #{form} keys" do
            parts = { layout_options: {}, nested: {}, properties: {}, call: {} }
            parts[higher][convert.call(id)] = 50
            parts[lower][convert.call(id)] = 70
            layout = parts[:layout_options].dup
            unless parts[:nested].empty?
              layout["properties"] = option_hash(parts[:nested], kind)
            end
            element = option_element_holding(
              layout_options: option_hash(layout, kind),
              properties: option_hash(parts[:properties], kind),
            )
            resolver = described_class.new(option_hash(parts[:call], kind))

            expect(resolver.get(id, element)).to eq(50.0)
          end
        end
      end
    end
  end

  describe "#report_unhonoured" do
    reported = "elk.selfLoopOffset"
    honoured = "elk.edgeRouting"
    report_spellings = [
      reported,
      "org.eclipse.elk.selfLoopOffset",
      *Elkrb::Options::Registry.all.fetch(reported).fetch(:aliases),
    ]
    # A Hash default that looks like an options map, nested one included.
    ghost = { "ghost.option" => 1, "properties" => { "ghost.option" => 1 } }
    log = nil
    warning = "elkrb: option #{reported} is accepted but not honoured in " \
              "this version"

    around do |example|
      log = StringIO.new
      previous = Elkrb.logger
      Elkrb.logger = Logger.new(
        log, level: Logger::DEBUG,
             formatter: ->(sev, _time, _prog, msg) { "#{sev} #{msg}\n" }
      )
      example.run
    ensure
      Elkrb.logger = previous
    end

    [nil, "properties", :properties].each do |nested_key|
      map_kinds.each do |kind|
        key_forms.each do |form, convert|
          report_spellings.each do |spelling|
            it "reports #{form} #{spelling} once under #{nested_key.inspect} " \
               "on a #{kind} map" do
              pairs = [[convert.call(spelling), 1]]
              graph = option_graph_holding(
                leaky_layout_options(nested_key, pairs, kind, ghost),
              )

              described_class.new({}).report_unhonoured(graph)

              expect(log.string).to eq("WARN #{warning}\n")
            end
          end

          orders.each do |order|
            it "reports every spelling of one id once under " \
               "#{nested_key.inspect} on a #{kind} map, #{form} keys, " \
               "#{order}" do
              pairs = report_spellings.map { |s| [convert.call(s), 1] }
              pairs.reverse! if order == :best_last
              options = leaky_layout_options(nested_key, pairs, kind, ghost)
              graph = option_graph_holding(options)

              described_class.new({}).report_unhonoured(graph)

              expect(log.string).to eq("WARN #{warning}\n")
            end
          end
        end

        it "reports nothing for an honoured key under #{nested_key.inspect} " \
           "on a #{kind} map, whatever its default holds" do
          options = leaky_layout_options(
            nested_key, [[honoured, "ORTHOGONAL"]], kind, ghost
          )
          graph = option_graph_holding(options)

          described_class.new({}).report_unhonoured(graph)

          expect(log.string).to eq("")
        end
      end
    end
  end
end
