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

  # Runs the CLI with one of its output streams closed before it writes a
  # byte, which is what a consumer like `| head -1` looks like from the
  # child's side. Returns the exit status.
  #
  # Open3.capture3 always keeps both streams open, so it cannot express this;
  # the point of the check is a stream that is NOT there.
  def run_elkrb_with_stream_closed(stream, *)
    read_end, write_end = IO.pipe
    read_end.close
    opts = { stream => write_end }
    pid = Process.spawn(RbConfig.ruby, "-I#{LIB}", EXE, *,
                        **opts, (stream == :out ? :err : :out) => File::NULL)
    write_end.close
    _, status = Process.waitpid2(pid)
    status.exitstatus
  end
end
