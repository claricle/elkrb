# frozen_string_literal: true

require "tmpdir"

# Skips an example when the filesystem refuses the DIRECTORY name it needs with
# EINVAL. Every other errno propagates; filename_probe_spec.rb is the authority
# on which, and pins them.
#
# Keep this. On the filesystems our macOS and Linux CI legs run on it never
# fires -- neither the `skip` call nor the rescue's `false` branch is reached --
# so it will look like dead code there. It is the only thing standing between
# the illegal-character examples in spec/cross_validation and an Errno::EINVAL
# on the Windows leg. Windows RESERVED names (CON, PRN, AUX, NUL, COM1-9,
# LPT1-9) are a different problem: they fail with an access error, not EINVAL,
# and this does not cover them.
#
# THE TRADE, stated so it is auditable: on Windows the guarded examples do not
# run, so the `base:` glob-escaping guarantee they pin is verified on macOS and
# Linux only. That is unavoidable -- a Windows path cannot hold `*` or `?`. No
# site falls to zero there: corpus_runner's two sites keep bracket and brace
# examples that predate this guard, and a bracket-class example was added to
# each importer, which had only one escape example apiece. Residual: on a host
# whose filesystem refuses these names for some other reason, the five skips
# are reported but nothing re-verifies the guarantee there.
#
# It asks the FILESYSTEM, not the platform, because that is the question, and
# the repo already draws that line (corpus_spec.rb probes case-folding rather
# than testing the OS).
#
# The supporting claim that a FAT or exFAT mount would refuse these names on any
# OS was a hypothesis, and it is now MEASURED FALSE for one case: a FAT16 image
# mounted on macOS via hdiutil ACCEPTS `*` and `?` in a directory name. So the
# refusal is a property of the OS layer, not of FAT itself, and asking the
# filesystem is still the right question -- it just answers yes here. No CI leg
# is known to use such a mount.
#
# Do not memoize: ~0.3 ms per call, and the spec stubs Dir.mkdir per example.
# See filename_probe_spec.rb for how to exercise the rescue from a test, and
# for why the rescue must stay inside the `mktmpdir` block.
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
