# frozen_string_literal: true

require "spec_helper"

RSpec.describe OptionRouteRows do
  describe ".expected_status" do
    subject(:status) { described_class.expected_status("opt", rows, moved) }

    let(:rows) do
      {
        "in-a" => [{}, true, "a"],
        "in-b" => [{}, true, "b"],
        "out-c" => [{}, false, "c"],
      }
    end
    let(:algorithms) { %w[a b] }

    before do
      allow(Elkrb::Options::Registry).to receive(:all)
        .and_return({ "opt" => { algorithms: algorithms } })
    end

    context "when every in-scope route moves and the other does not" do
      let(:moved) { { "in-a" => true, "in-b" => true, "out-c" => false } }

      it { is_expected.to eq(:honoured) }
    end

    context "when no in-scope route moves and the other does" do
      let(:moved) { { "in-a" => false, "in-b" => false, "out-c" => true } }

      it { is_expected.to eq(:accepted) }
    end

    context "when only some in-scope routes move" do
      let(:moved) { { "in-a" => true, "in-b" => false, "out-c" => true } }

      it { is_expected.to eq(:partial) }
    end

    context "when the entry is generic, so every algorithm is in scope" do
      let(:moved) { { "in-a" => true, "in-b" => true, "out-c" => false } }
      let(:algorithms) { :all }

      it { is_expected.to eq(:partial) }
    end

    context "when the rows come from .rows and a compound_other route moves" do
      let(:rows) do
        described_class.rows(
          id: "opt", internal: "opt_internal", shapes: { value: [5, 80] },
          algorithms: Elkrb::Layout::AlgorithmRegistry.available_algorithms,
          readers: { [:compound_other, "opt_internal", :value] => %w[layered] }
        )
      end
      let(:moved) { rows.transform_values { |row| row[1] } }

      context "with the algorithm that route sets in scope" do
        let(:algorithms) { %w[layered] }

        it { is_expected.to eq(:partial) }
      end

      context "with only the root algorithm, fixed, in scope" do
        let(:algorithms) { %w[fixed] }

        it { is_expected.to eq(:accepted) }
      end
    end

    context "when the scope names an algorithm no row probes" do
      let(:moved) { { "in-a" => true, "in-b" => true, "out-c" => true } }
      let(:algorithms) { %w[a typo] }

      it "raises rather than quietly narrow the scope" do
        expect { status }.to raise_error(ArgumentError, /no row for.*typo/)
      end
    end

    context "when the scope is empty" do
      let(:moved) { { "in-a" => true, "in-b" => true, "out-c" => true } }
      let(:algorithms) { [] }

      it "raises rather than report :honoured" do
        expect { status }.to raise_error(ArgumentError, /no row in scope/)
      end
    end
  end
end
