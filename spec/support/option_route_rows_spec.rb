# frozen_string_literal: true

require "spec_helper"

RSpec.describe OptionRouteRows do
  describe ".expected_status" do
    subject(:status) { described_class.expected_status("opt", rows, moved) }

    let(:rows) do
      {
        "in-a" => [{}, true, "a", true],
        "in-b" => [{}, true, "b", true],
        "out-c" => [{}, false, "c", true],
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
          spellings: %w[opt opt_internal], shapes: { value: [5, 80] },
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

    context "when a route's carrier does not apply to the option" do
      let(:rows) do
        {
          "graph" => [{}, true, "a", true],
          "edge" => [{}, false, "a", false],
        }
      end
      let(:algorithms) { %w[a] }

      context "and only that route does not move" do
        let(:moved) { { "graph" => true, "edge" => false } }

        it "is :honoured, which no applicable route contradicts" do
          expect(status).to eq(:honoured)
        end
      end

      context "and only that route moves" do
        let(:moved) { { "graph" => false, "edge" => true } }

        it { is_expected.to eq(:accepted) }
      end

      context "and an applicable route does not move" do
        let(:rows) do
          super().merge("compound" => [{}, false, "a", true])
        end
        let(:moved) do
          { "graph" => true, "edge" => false, "compound" => false }
        end

        it { is_expected.to eq(:partial) }
      end

      context "and no route applies" do
        let(:rows) { { "edge" => [{}, false, "a", false] } }
        let(:moved) { { "edge" => false } }

        it "raises rather than report :honoured" do
          expect { status }.to raise_error(ArgumentError, /no row in scope/)
        end
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

  describe ".rows" do
    subject(:rows) do
      described_class.rows(
        spellings: %w[elk.padding padding],
        shapes: { first: [1, 2], second: [3, 4], third: [5, 6] },
        algorithms: %w[box layered], readers: {}, **extra
      )
    end

    let(:extra) { {} }

    it "probes every shape at every positioning" do
      probed = rows.keys.map { |label| label.split.values_at(2, 3) }.uniq

      expect(probed).to match_array(
        %w[first second third].product(
          %w[positioned=true positioned=false positioned=some],
        ),
      )
    end

    it "lays each row out at the positioning its label names" do
      by_label = rows.to_h do |label, (args, *)|
        [label.split[3], args[:positioned]]
      end

      expect(by_label).to eq("positioned=true" => true,
                             "positioned=false" => false,
                             "positioned=some" => :some)
    end

    it "marks every carrier as applying by default" do
      expect(rows.values.map(&:last).uniq).to eq([true])
    end

    context "with the carriers the option applies to" do
      let(:extra) { { carriers: %i[root call_symbol] } }

      it "marks only rows of those carriers as applying" do
        applying = rows.select { |_, row| row.last }.keys

        expect(applying.map { |label| label.split.first }.uniq)
          .to match_array(%w[root call_symbol])
      end

      it "still probes the carriers it does not apply to" do
        expect(rows.keys.map { |label| label.split.first }.uniq)
          .to match_array(described_class::CARRIERS.map(&:to_s))
      end
    end

    context "with a carrier that does not exist" do
      let(:extra) { { carriers: %i[root typo] } }

      it "raises rather than silently narrow the scope" do
        expect { rows }.to raise_error(ArgumentError, /not carriers: \[:typo\]/)
      end
    end

    context "with no carrier" do
      let(:extra) { { carriers: [] } }

      it "raises rather than leave every status unobserved" do
        expect { rows }.to raise_error(ArgumentError, /no carrier applies/)
      end
    end
  end
end
