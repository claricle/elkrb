# frozen_string_literal: true

require "open3"
require "rbconfig"

# Runs the real `exe/elkrb` executable as a subprocess.
#
# Every example in cli_spec.rb exercises the actual CLI boundary (argv,
# exit status, stdout/stderr separation) instead of calling into Thor
# methods directly, so it proves what a shell caller actually observes.
module CliRunner
  ROOT = File.expand_path("../..", __dir__)
  LIB = File.join(ROOT, "lib")
  EXE = File.join(ROOT, "exe/elkrb")

  def run_elkrb(*, stdin: nil, env: {})
    capture_opts = stdin.nil? ? {} : { stdin_data: stdin }
    Open3.capture3(env, RbConfig.ruby, "-I#{LIB}", EXE, *, **capture_opts)
  end
end
