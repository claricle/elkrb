# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# Puts a fake `dot` executable first on PATH for the duration of a block.
#
# The fake script logs its argv (NUL-separated, one invocation per line) to
# a log file and touches whatever file the real Graphviz `-o` flag would
# have written, in both forms elkrb has used for it: a separate `-o path`
# token pair, and the `-opath` suffix form. Given `-V`, it prints a canned
# version line, matching what `dot -V` actually prints. Specs read the log
# to assert what argv the CLI actually built, without stubbing the method
# under test.
module FakeDot
  FAKE_DOT_SCRIPT = <<~'RUBY'
    #!/usr/bin/env ruby
    # frozen_string_literal: true
    require "fileutils"

    File.open(ENV.fetch("FAKE_DOT_LOG"), "a") { |f| f.write("#{ARGV.join("\0")}\n") }

    warn "dot - graphviz version 2.44.1 (20200629.0846)" if ARGV == ["-V"]

    ARGV.each_with_index do |arg, i|
      if arg == "-o"
        FileUtils.touch(ARGV[i + 1]) if ARGV[i + 1]
      elsif arg.start_with?("-o") && arg.length > 2
        FileUtils.touch(arg.delete_prefix("-o"))
      end
    end
  RUBY

  def with_fake_dot
    original_path = ENV["PATH"]
    original_log = ENV["FAKE_DOT_LOG"]
    original_elkrb_dot = ENV["ELKRB_DOT"]

    Dir.mktmpdir("fake_dot") do |dir|
      log_path = File.join(dir, "dot.log")
      script_path = File.join(dir, "dot")
      File.write(script_path, FAKE_DOT_SCRIPT)
      FileUtils.chmod(0o755, script_path)

      ENV["PATH"] = [dir, original_path].compact.join(File::PATH_SEPARATOR)
      ENV["FAKE_DOT_LOG"] = log_path
      ENV.delete("ELKRB_DOT")

      yield log_path
    ensure
      ENV["PATH"] = original_path
      ENV["FAKE_DOT_LOG"] = original_log
      ENV["ELKRB_DOT"] = original_elkrb_dot
    end
  end
end
