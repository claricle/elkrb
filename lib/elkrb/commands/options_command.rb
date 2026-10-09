# frozen_string_literal: true

require "json"

require_relative "../errors"
require_relative "../options/registry"
require_relative "../layout/algorithm_registry"

module Elkrb
  module Commands
    # Prints the layout option registry: every option elkrb knows, its type,
    # default and truthfulness status, optionally narrowed to one algorithm.
    class OptionsCommand
      COLUMNS = %w[id type default status aliases].freeze
      private_constant :COLUMNS

      def initialize(algorithm, options)
        @algorithm = algorithm
        @options = options
      end

      def run
        puts @options[:json] ? JSON.generate("options" => rows) : table(rows)
      end

      private

      def rows
        owners = owners_by_option
        ids.map { |id| row(id, owners.fetch(id, [])) }
      end

      def row(id, algorithms)
        entry = Options::Registry.all.fetch(id)
        {
          "id" => id,
          "type" => entry[:type].to_s,
          "default" => entry[:default],
          "status" => entry[:status].to_s,
          "aliases" => Array(entry[:aliases]),
          "algorithms" => algorithms,
        }
      end

      def ids
        return Options::Registry.all.keys unless @algorithm

        info = Layout::AlgorithmRegistry.algorithm_info(@algorithm)
        raise AlgorithmNotFoundError, @algorithm unless info

        info[:supported_options]
      end

      # option id => ids of the registered algorithms that support it
      def owners_by_option
        Layout::AlgorithmRegistry.all_algorithm_info
          .each_with_object(Hash.new { |h, k| h[k] = [] }) do |info, owners|
          info[:supported_options].each { |id| owners[id] << info[:id] }
        end
      end

      def table(rows)
        lines = [COLUMNS, *rows.map { |row| cells(row) }]
        widths = column_widths(lines)
        lines.map { |line| pad(line, widths) }
      end

      def column_widths(lines)
        lines.transpose.map { |column| column.map(&:length).max }
      end

      def pad(line, widths)
        line.zip(widths).map { |text, width| text.ljust(width) }
          .join("  ").rstrip
      end

      def cells(row)
        [row["id"], row["type"], display(row["default"]), row["status"],
         row["aliases"].join(",")]
      end

      def display(value)
        value.nil? ? "-" : value.to_s
      end
    end
  end
end
