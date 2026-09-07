# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# Puts a fake `dot` executable first on PATH for the duration of a block.
#
# The fake script logs its argv (NUL-separated, one invocation per line) to
# a log file and touches whatever file the real Graphviz `-o` flag would
# have written, in both forms elkrb has used for it: a separate `-o path`
# token pair, and the `-opath` suffix form. Specs read the log to assert
# what argv the CLI actually built, without stubbing the method under test.
module FakeDot
  FAKE_DOT_SCRIPT = <<~'RUBY'
    #!/usr/bin/env ruby
    # frozen_string_literal: true
    require "fileutils"

    File.open(ENV.fetch("FAKE_DOT_LOG"), "a") { |f| f.write("#{ARGV.join("\0")}\n") }

    ARGV.each_with_index do |arg, i|
      if arg == "-o"
        FileUtils.touch(ARGV[i + 1]) if ARGV[i + 1]
      elsif arg.start_with?("-o") && arg.length > 2
        FileUtils.touch(arg.delete_prefix("-o"))
      end
    end
  RUBY

  def with_fake_dot
    original_path = ENV.fetch("PATH", nil)
    original_log = ENV.fetch("FAKE_DOT_LOG", nil)

    Dir.mktmpdir("fake_dot") do |dir|
      yield install_fake_dot(dir)
    ensure
      ENV["PATH"] = original_path
      ENV["FAKE_DOT_LOG"] = original_log
    end
  end

  private

  # Writes the script into `dir`, puts `dir` first on PATH, and returns the
  # log path the caller reads argv from. PATH is still the original here --
  # with_fake_dot only restores it after the block.
  def install_fake_dot(dir)
    script_path = File.join(dir, "dot")
    File.write(script_path, FAKE_DOT_SCRIPT)
    FileUtils.chmod(0o755, script_path)

    log_path = File.join(dir, "dot.log")
    search_path = [dir, ENV.fetch("PATH", nil)].compact
    ENV["PATH"] = search_path.join(File::PATH_SEPARATOR)
    ENV["FAKE_DOT_LOG"] = log_path
    log_path
  end
end
