# frozen_string_literal: true

require "spec_helper"
require "open3"

# These shell out on purpose. Asserting `defined?` in-process proves nothing:
# elkt_serializer_spec.rb and validate_command.rb both require the parser at
# runtime, and spec_helper randomises order, so the constant may already exist
# for reasons unrelated to lib/elkrb.rb.
ELKRB_ROOT = File.expand_path("../../..", __dir__)

RSpec.describe "ELKT loading" do
  def ruby(script)
    Open3.capture3("ruby", "-I#{ELKRB_ROOT}/lib", "-e", script,
                   chdir: ELKRB_ROOT)
  end

  it "loads the parser and the ELKT serializer from require \"elkrb\"" do
    stdout, _stderr, status = ruby(<<~RUBY)
      require "elkrb"
      print [defined?(Elkrb::Parsers::ElktParser),
             defined?(Elkrb::Serializers::ElktSerializer)].join(",")
    RUBY

    expect(status).to be_success
    expect(stdout).to eq("constant,constant")
  end

  # A require-only probe stays green even with every require deleted, because
  # constants inside method bodies resolve lazily. So this parses real input
  # and forces a raise.
  it "parses and raises when the parser is required on its own" do
    stdout, _stderr, status = ruby(<<~RUBY)
      require "elkrb/parsers/elkt_parser"
      print Elkrb::Parsers::ElktParser.parse("node a\\n")[:children].first[:id]
      begin
        Elkrb::Parsers::ElktParser.parse("<x>")
      rescue Elkrb::ParseError
        print ",ParseError"
      end
    RUBY

    expect(status).to be_success
    expect(stdout).to eq("a,ParseError")
  end

  it "exits 1 and reports the location for an unparseable .elkt file" do
    fixture = "#{ELKRB_ROOT}/spec/fixtures/elkt/invalid/garbage.elkt"
    # error_output is Thor's `say`, so the CLI writes this to stdout.
    stdout, _stderr, status = Open3.capture3(
      "ruby", "-I#{ELKRB_ROOT}/lib", "#{ELKRB_ROOT}/exe/elkrb", "validate",
      fixture, chdir: ELKRB_ROOT
    )

    expect(status.exitstatus).to eq(1)
    expect(stdout).to match(/line \d+, column \d+/)
  end
end
