# frozen_string_literal: true

# The argv for each cell of the command matrix in spec/elkrb/cli/matrix_spec.rb.
# A cell is nil where the command has no such input (`version` has no file to
# miss), and the spec skips it rather than inventing a stand-in.
module CliMatrix
  CASES = %i[ok missing_file unknown_algorithm bad_flag].freeze

  # @param graph [String] path of a valid graph file
  # @param dot [String] path of a valid DOT file
  # @param dir [String] a scratch directory holding `graph`
  # @return [Hash{String => Hash{Symbol => Array<String>, nil}}]
  def self.argv(graph:, dot:, dir:)
    out = File.join(dir, "out")
    to_dot = ["-o", "#{out}.dot"]
    to_yml = ["-o", "#{out}.yml"]
    to_svg = ["-o", "#{out}.svg"]
    batch = ["batch", dir, "--output-dir", out]
    {
      "layout" => {
        ok: ["layout", graph],
        missing_file: ["layout", File.join(dir, "absent.json")],
        unknown_algorithm: ["layout", graph, "--algorithm", "nosuch"],
        bad_flag: ["layout", graph, "--bogus"],
      },
      "diagram" => {
        ok: ["diagram", graph, *to_dot],
        missing_file: ["diagram", File.join(dir, "absent.json"), *to_dot],
        unknown_algorithm: ["diagram", graph, *to_dot, "--algorithm", "nosuch"],
        bad_flag: ["diagram", graph, *to_dot, "--bogus"],
      },
      "convert" => {
        ok: ["convert", graph, *to_yml],
        missing_file: ["convert", File.join(dir, "absent.json"), *to_yml],
        unknown_algorithm: nil,
        bad_flag: ["convert", graph, *to_yml, "--bogus"],
      },
      "render" => {
        ok: ["render", dot, *to_svg],
        missing_file: ["render", File.join(dir, "absent.dot"), *to_svg],
        unknown_algorithm: nil,
        bad_flag: ["render", dot, *to_svg, "--bogus"],
      },
      "validate" => {
        ok: ["validate", graph],
        missing_file: ["validate", File.join(dir, "absent.json")],
        unknown_algorithm: nil,
        bad_flag: ["validate", graph, "--bogus"],
      },
      "batch" => {
        ok: [*batch, "--format", "dot"],
        missing_file: ["batch", File.join(dir, "absent"), "--output-dir", out],
        unknown_algorithm: [*batch, "--algorithm", "nosuch"],
        bad_flag: [*batch, "--bogus"],
      },
      "version" => {
        ok: ["version"], missing_file: nil, unknown_algorithm: nil,
        bad_flag: ["version", "--bogus"]
      },
      "algorithms" => {
        ok: ["algorithms"], missing_file: nil, unknown_algorithm: nil,
        bad_flag: ["algorithms", "--bogus"]
      },
      "options" => {
        ok: ["options"], missing_file: nil,
        unknown_algorithm: %w[options nosuch],
        bad_flag: ["options", "--bogus"]
      },
    }
  end
end
