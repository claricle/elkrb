# frozen_string_literal: true

require "json"

# Each case in the fixture holds a connected graph whose layers mix node
# sizes, and the node positions elkjs 0.11.0 computed for it. Nodes with
# more outgoing than incoming edges lean toward the far side of their layer.
RSpec.describe "Layered node alignment against elkjs" do
  cases = JSON.parse(
    File.read(File.expand_path("../../../fixtures/layered_alignment/cases.json",
                               __dir__)),
  )

  cases.each do |example|
    it "places #{example['name']} like elkjs" do
      result = Elkrb.layout(example["graph"])
      placed = result.children.to_h { |node| [node.id, [node.x, node.y]] }

      within = example["positions"].transform_values do |point|
        point.map { |value| be_within(1e-6).of(value) }
      end

      expect(placed).to match(within)
    end
  end
end
