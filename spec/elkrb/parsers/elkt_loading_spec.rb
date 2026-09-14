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
    # PR #13's own commit eefcfd1 ("exit non-zero on cli errors, route
    # diagnostics to stderr") deliberately moved error_output off Thor's
    # `say` and onto $stderr.puts -- keep asserting stderr, not stdout.
    # What #13 used to lose on this exact path was the LOCATION: FormatSniffer
    # flattened the parser's own located Elkrb::ParseError into a generic
    # "Unable to parse input file" message. Fixed to keep both: the
    # deliberate stream and the parser's own diagnostic. Pin the exact
    # message, not just the pattern -- "line \d+, column \d+" alone would
    # equally match a message with the wrong character or the wrong column.
    stdout, stderr, status = Open3.capture3(
      "ruby", "-I#{ELKRB_ROOT}/lib", "#{ELKRB_ROOT}/exe/elkrb", "validate",
      fixture, chdir: ELKRB_ROOT
    )

    expect(status.exitstatus).to eq(1)
    expect(stdout).to eq("")
    expect(stderr)
      .to eq(%(Error: Unexpected character "!" at line 1, column 34\n))
  end

  it "exits 1 with the generic message for content with no location to give" do
    # A non-String reaching the parser (Lexer::initialize's TypeError) has
    # no line/column to preserve -- the generic fallback stays the correct
    # shape for THAT case, so the two must not silently collapse into one.
    stdout, _stderr, status = ruby(<<~RUBY)
      require "elkrb/format_sniffer"
      begin
        Elkrb::FormatSniffer.send(:parse_elkt_declared!, nil)
      rescue ArgumentError => e
        print e.message
      end
    RUBY

    expect(status).to be_success
    expect(stdout)
      .to eq("Unable to parse input file. Supported formats: JSON, YAML, ELKT")
  end
end
