# frozen_string_literal: true

require "tmpdir"

# Skips an example when the filesystem refuses the DIRECTORY name it needs with
# EINVAL. Every other errno propagates; filename_probe_spec.rb pins which.
#
# Keep this. It never fires on the macOS and Linux CI legs, so it will look like
# dead code there. It is the only thing standing between the illegal-character
# examples in spec/cross_validation and an Errno::EINVAL on the Windows leg.
#
# It does NOT cover Windows reserved names (CON, PRN, AUX, NUL, COM1-9,
# LPT1-9), which fail with an access error rather than EINVAL.
#
# The trade: on Windows the guarded examples do not run, so the `base:`
# glob-escaping guarantee is verified on macOS and Linux only. A Windows path
# cannot hold `*` or `?`, so this is unavoidable. No site falls to zero --
# corpus_runner keeps bracket and brace examples, and each importer carries a
# bracket-class one.
#
# It asks the FILESYSTEM, not the platform, matching corpus_spec.rb, which
# probes case-folding rather than testing the OS.
#
# Do not memoize: the spec stubs Dir.mkdir per example. See
# filename_probe_spec.rb for why the rescue must stay inside the mktmpdir block.
module FilenameProbe
  def skip_unless_creatable(name)
    return if creatable?(name)

    skip "the filesystem under #{Dir.tmpdir} refuses a directory " \
         "named #{name.inspect}"
  end

  private

  def creatable?(name)
    Dir.mktmpdir do |probe|
      Dir.mkdir(File.join(probe, name))
      true
    rescue Errno::EINVAL
      false
    end
  end
end
