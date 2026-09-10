# frozen_string_literal: true

require "spec_helper"
require "support/filename_probe"
require "tmpdir"

# This guard fails SILENTLY GREEN, which is why it earns a spec of its own.
# Invert its condition -- `return unless creatable?(name)` -- and on a
# filesystem that ACCEPTS these names, which is every CI leg except Windows,
# all five illegal-character examples stop running while the suite still exits
# 0: measured on this tree, "0 failures, 5 pending". (On a filesystem that
# refuses them the inverted guard returns into fixture creation and fails
# loudly instead -- 5 failures, 0 pending -- so the silence is specific to the
# hosts we actually run the suite on.) Nothing else in the suite sees it.
#
# The host is a plain class rather than a real example group because RSpec
# turns a real `skip` into a pending example, leaving nothing to assert. A
# stand-in that defines its own `skip` is never intercepted.
RSpec.describe FilenameProbe do
  let(:host) do
    Class.new do
      include FilenameProbe

      attr_reader :skipped

      def skip(message = nil)
        @skipped = message
      end
    end.new
  end

  # Deliberately NOT one of the five guarded names: those are skipped on the
  # Windows leg and this example has to run there.
  let(:legal_name) { "probe[x]dir" }

  # Refuse one basename and let every other mkdir through. An unconditional
  # stub breaks Dir.mktmpdir, which calls Dir.mkdir internally, so the errno
  # would escape before the probe's own call and invert the construction.
  def refuse(name, with: Errno::EINVAL)
    allow(Dir).to receive(:mkdir).and_wrap_original do |original, path, *rest|
      raise with, path if File.basename(path) == name

      original.call(path, *rest)
    end
  end

  # `not_to receive`, not `skipped.to be_nil`. Since `skip` takes an optional
  # message, a mutant calling it with no argument leaves `skipped` nil and a
  # nil-check passes while all five guarded examples silently go pending.
  it "does not skip when the filesystem accepts the name" do
    expect(host).not_to receive(:skip)

    host.skip_unless_creatable(legal_name)
  end

  it "skips when the filesystem refuses the name with EINVAL" do
    refuse("refused*dir")

    host.skip_unless_creatable("refused*dir")

    expect(host.skipped).to eq(
      "the filesystem under #{Dir.tmpdir} refuses a directory " \
      'named "refused*dir"',
    )
  end

  # A rescue broad enough to swallow these would report "not creatable" for a
  # failure that has nothing to do with the name, and skip instead of surfacing
  # the real fault. One errno cannot pin that: a variant rescuing EINVAL,
  # ENAMETOOLONG and ENOENT passes a single-errno check clean.
  [Errno::EACCES, Errno::EILSEQ, Errno::ENAMETOOLONG, Errno::ENOENT,
   Errno::EEXIST, Errno::EPERM].each do |errno|
    it "propagates #{errno} rather than treating it as a refusal" do
      refuse("odd*dir", with: errno)

      expect(host).not_to receive(:skip)

      expect { host.skip_unless_creatable("odd*dir") }.to raise_error(errno)
    end
  end

  # Pins the rescue INSIDE the mktmpdir block. Lifted to the method it would
  # swallow this and skip for a reason unrelated to the name -- and RuboCop
  # passes that form clean, so lint will not catch it.
  it "propagates a failure of mktmpdir itself" do
    allow(Dir).to receive(:mktmpdir).and_raise(Errno::EINVAL, "broken TMPDIR")

    expect(host).not_to receive(:skip)

    expect { host.skip_unless_creatable(legal_name) }
      .to raise_error(Errno::EINVAL)
  end
end
