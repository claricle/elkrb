# frozen_string_literal: true

RSpec.describe "generated docs" do
  let(:registry) { Elkrb::Options::Registry }

  ElkrbDocs::PAGES.each_key do |file|
    it "renders #{file} identically twice" do
      expect(rendered(file)).to eq(rendered(file))
    end
  end

  describe "OPTIONS.adoc" do
    let(:page) { rendered("OPTIONS.adoc") }

    it "has a row for every registry option" do
      missing = registry.all.keys.reject do |id|
        page.include?("\n|`+#{id}+`\n")
      end
      expect(missing).to eq([])
    end

    it "lists an option's aliases, status and note in its row" do
      row = page[/^\|`\+elk\.direction\+`\n.*?\n\n/m]
      expect(row).to include("|`+direction+`\n", "|partial\n",
                             registry.note("elk.direction"))
    end

    it "does not let a pipe in a cell start a new cell" do
      expect(ElkrbDocs::OptionsPage.escape("a|b")).to eq("a\\|b")
    end
  end

  describe "COMPATIBILITY.adoc" do
    let(:page) { rendered("COMPATIBILITY.adoc") }
    let(:cases) { GoldenCases::COMPARISON_CASES + [GoldenCases::ERROR_CASE] }

    it "has a row for every golden case" do
      missing = GoldenCases::ALL_NAMES.reject do |name|
        page.include?("\n|`#{name}`\n")
      end
      expect(missing).to eq([])
    end

    it "gives each pending case its reason and no other case one" do
      row = /^\|`(\w+)`\n\|[^\n]*\n\|[^\n]*\n\|(match|pending)\n\|([^\n]*)\n/
      rendered_rows = page.scan(row).to_h do |name, status, reason|
        [name, [status, reason]]
      end
      expected = cases.to_h do |kase|
        outcome = kase[:pending] ? ["pending", kase[:pending]] : ["match", ""]
        [kase[:name], outcome]
      end
      expect(rendered_rows).to eq(expected)
    end

    it "groups each case under the algorithm its input selects" do
      expect(page).to match(/^== stress\n\n.*?`stress_path4`/m)
    end
  end
end
