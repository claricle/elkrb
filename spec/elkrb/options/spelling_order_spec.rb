# frozen_string_literal: true

require "spec_helper"

# Every spelling the registry accepts for an id has one place in the order, so
# two spellings of one id in one map have one winner whatever order they were
# written in. Swept over every registered id: a rule measured on one id misses
# the ids whose shorter spellings are suffixes of the id.
RSpec.describe Elkrb::Options::OptionMap, "spelling order" do
  registry = Elkrb::Options::Registry
  long_prefix = "org.eclipse.elk."

  # Best first: the id, its org.eclipse.elk. form, the aliases in registry
  # order, then the dot-suffixes of the id from the most qualified down.
  ordered_spellings = lambda do |id|
    parts = id.split(".")
    suffixes = (1...parts.size).map { |from| parts[from..].join(".") }
    long = id.start_with?("elk.") ? long_prefix + id.delete_prefix("elk.") : nil
    aliases = Array(registry.all.fetch(id)[:aliases])
    [id, long, *aliases, *suffixes]
      .compact.uniq.select { |name| registry.canonical(name) == id }
  end

  key_forms = { "String" => :to_s.to_proc, "Symbol" => :to_sym.to_proc }

  it "finds the suffix spellings the sweep exists for" do
    expect(ordered_spellings.call("elk.layered.spacing.nodeNodeBetweenLayers"))
      .to eq(%w[
               elk.layered.spacing.nodeNodeBetweenLayers
               org.eclipse.elk.layered.spacing.nodeNodeBetweenLayers
               layer_spacing
               layered.spacing.nodeNodeBetweenLayers
               spacing.nodeNodeBetweenLayers
               nodeNodeBetweenLayers
             ])
  end

  it "gives every spelling of every id its own place in the order" do
    spellings = Elkrb::Options::Spellings.new
    shared = registry.all.keys.filter_map do |id|
      names = ordered_spellings.call(id)
      ranks = names.map { |name| spellings.resolve(name).last }
      id unless ranks == ranks.uniq.sort
    end

    expect(shared).to eq([])
  end

  it "resolves two spellings of every id to the better one in either order" do
    wrong = []
    registry.all.each_key do |id|
      spellings = ordered_spellings.call(id)
      spellings.combination(2) do |better, worse|
        key_forms.each_value do |better_form|
          key_forms.each_value do |worse_form|
            pairs = [[better_form.call(better), 1], [worse_form.call(worse), 2]]
            [pairs, pairs.reverse].each do |entries|
              map = described_class.new(entries.to_h, Elkrb::Options::Spellings.new)
              wrong << [id, better, worse] unless map.value(id) == 1
            end
          end
        end
      end
    end

    expect(wrong.uniq).to eq([])
  end
end
