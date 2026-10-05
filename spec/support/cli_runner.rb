# frozen_string_literal: true

require "open3"
require "rbconfig"

# Runs elkrb in a real subprocess.
#
# `run_elkrb` drives the actual `exe/elkrb` executable, so every example in
# cli_spec.rb exercises the real CLI boundary (argv, exit status,
# stdout/stderr separation) instead of calling into Thor methods directly.
#
# `run_ruby` drives an arbitrary library caller the same way. It exists so a
# spec can prove that elkrb does not terminate the process it is called from.
# A separate process is not the only way to tell "raised" from "killed": an
# in-process `rescue SystemExit` sees a direct `exit`, and its status. But
# rescuing it changes what is being measured, an unrescued one takes the RSpec
# runner with it, and neither form sees a status decided during SHUTDOWN --
# `at_exit { exit 7 }` lets the call return normally and still exits 7. Only a
# real child process reports that.
module CliRunner
  ROOT = File.expand_path("../..", __dir__)
  LIB = File.join(ROOT, "lib")
  EXE = File.join(ROOT, "exe/elkrb")

  # Printed by a child AFTER the call under test. A killed process cannot
  # print it, which is what makes its presence a proof rather than an
  # absence check. Defined on the module, not inside an example group, where
  # Lint/ConstantDefinitionInBlock would report it.
  SENTINEL = "SENTINEL-CALLER-SURVIVED"

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

  # `chdir: ROOT` keeps a relative path in `source` (the Rakefile) resolving
  # against the checkout under test rather than the runner's cwd.
  def run_ruby(source)
    Open3.capture3(RbConfig.ruby, "-I#{LIB}", "-e", source, chdir: ROOT)
  end
end
