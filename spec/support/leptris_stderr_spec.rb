# frozen_string_literal: true

require "spec_helper"

RSpec.describe "stderr equality ignoring the leptris fallback warning" do
  let(:warning) do
    "leptris: native acceleration unavailable " \
      "(leptris: no native_4_0 bundle in this install); using the FFI surface\n"
  end
  let(:error) { "Error: invalid input\nTry: elkrb help layout\n" }

  it "accepts empty stderr and the fallback warning alone" do
    expect("").to eq_ignoring_leptris_warning("")
    expect(warning).to eq_ignoring_leptris_warning("")
    expect(warning.gsub("\n", "\r\n")).to eq_ignoring_leptris_warning("")
  end

  it "preserves the exact expected diagnostic alongside the warning" do
    expect(error).to eq_ignoring_leptris_warning(error)
    expect(warning + error).to eq_ignoring_leptris_warning(error)
    expect(error + warning).to eq_ignoring_leptris_warning(error)
  end

  it "rejects every additional diagnostic, including whitespace" do
    ["unexpected warning\n", "Error: failed\n", "\n", " "].each do |extra|
      expect(extra).not_to eq_ignoring_leptris_warning("")
      expect(warning + extra).not_to eq_ignoring_leptris_warning("")
      expect(extra + warning).not_to eq_ignoring_leptris_warning("")
      expect(warning + error + extra).not_to eq_ignoring_leptris_warning(error)
    end
  end

  it "rejects near matches and embedded or incomplete warning lines" do
    ["prefix #{warning}", warning.chomp,
     warning.sub("; using the FFI surface", ""),
     warning.sub("leptris:", "another-library:"),
     warning.sub("bundle", "bundle\nunexpected error")].each do |other|
      expect(other).not_to eq_ignoring_leptris_warning("")
    end
  end

  it "still rejects missing, changed, or reordered CLI diagnostics" do
    expect(warning).not_to eq_ignoring_leptris_warning(error)
    expect(warning + error.sub("invalid", "different"))
      .not_to eq_ignoring_leptris_warning(error)
    expect(warning + error.lines.reverse.join)
      .not_to eq_ignoring_leptris_warning(error)
  end
end
