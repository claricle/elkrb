# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Elkrb.logger" do
  include CliRunner

  it "defaults to WARN, so only unhonoured options are reported" do
    stdout, stderr, status =
      run_ruby("require 'elkrb'; puts Elkrb.logger.level")

    expect([stdout.strip, status.exitstatus, stderr])
      .to eq([Logger::WARN.to_s, 0, ""])
  end

  it "writes to stderr, never stdout" do
    stdout, stderr, = run_ruby('require "elkrb"; Elkrb.logger.warn("hello")')

    expect([stdout, stderr]).to match([eq(""), /hello/])
  end

  it "can be replaced" do
    custom = Logger.new(StringIO.new)
    previous = Elkrb.logger
    Elkrb.logger = custom

    expect(Elkrb.logger).to be(custom)
  ensure
    Elkrb.logger = previous
  end
end
