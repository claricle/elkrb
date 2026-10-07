# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "Elkrb.logger" do
  def run_ruby(code)
    root = File.expand_path("../..", __dir__)
    Open3.capture3(RbConfig.ruby, "-I", File.join(root, "lib"),
                   "-relkrb", "-e", code)
  end

  it "defaults to WARN, so only unhonoured options are reported" do
    stdout, stderr, status = run_ruby("puts Elkrb.logger.level")

    expect([stdout.strip, status.exitstatus, stderr])
      .to eq([Logger::WARN.to_s, 0, ""])
  end

  it "writes to stderr, never stdout" do
    stdout, stderr, = run_ruby('Elkrb.logger.warn("hello")')

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
