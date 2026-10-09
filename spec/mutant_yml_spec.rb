# frozen_string_literal: true

require "rbconfig"
require "yaml"

# `mutant.yml`'s `requires:` list is what `rake mutant` loads before it looks
# for subjects. `require "elkrb"` alone does not load the CLI, its lazily
# required commands, or GraphvizWrapper -- lib/elkrb.rb deliberately never
# requires the CLI (exe/elkrb does that) and the CLI only requires each
# command inside the Thor method that needs it. Measured on origin/v2 before
# this file existed: `bundle exec rake mutant` against a real, uncommitted
# change to lib/elkrb/cli.rb reported `Subjects: 0, Coverage: 100.00%,
# exit 0` -- a gate that cannot fail, reporting success.
#
# This spec pins the property directly, out of process, so it fails the
# moment a NEW lazily-loaded file appears under lib/ without a matching
# entry here -- the same silent gap this file exists to close, one file
# later. In-process would not do: this process has already required plenty
# of lib/ files via other specs before this one runs, so `$LOADED_FEATURES`
# would read as complete regardless of what mutant.yml actually declares.
RSpec.describe "mutant.yml requires" do
  let(:repo_root) { File.expand_path("..", __dir__) }
  let(:requires) do
    YAML.safe_load_file(File.join(repo_root, "mutant.yml"))["requires"]
  end
  let(:probe_result) do
    probe = <<~RUBY
      requires = #{requires.inspect}
      requires.each { |r| require r }
      puts $LOADED_FEATURES
    RUBY

    out = IO.popen(
      ["bundle", "exec", RbConfig.ruby, "-Ilib", "-e", probe],
      chdir: repo_root,
      err: %i[child out],
      &:read
    )

    [out, $CHILD_STATUS]
  end
  let(:probe_output) { probe_result.fetch(0) }
  subject(:loaded_lib_files) do
    probe_output.lines(chomp: true).filter_map do |feature|
      path = feature.delete_suffix("\r").tr("\\", "/")
      path[%r{(?:\A|/)lib/(elkrb(?:/.*)?\.rb)\z}, 1]
    end.sort
  end

  it "loads every file under lib/ once mutant.yml's requires: run" do
    expect(probe_result.fetch(1)).to be_success,
                                     "subprocess failed:\n#{probe_output}"
    all_lib_files = Dir.glob("**/*.rb", base: File.join(repo_root, "lib")).sort
    missing = all_lib_files - loaded_lib_files

    expect(missing).to eq([]), "mutant.yml's requires do not load: " \
                               "#{missing.join(', ')} -- rake mutant will " \
                               "silently report 0 subjects for these files"
  end

  context "with Windows loaded-feature paths" do
    let(:probe_output) do
      [
        "D:\\a\\elkrb\\elkrb\\lib\\elkrb.rb\r\n",
        "lib\\elkrb\\cli.rb\r\n",
        "D:/a/elkrb/elkrb/lib\\elkrb\\version.rb\r\r\n",
        "D:\\Ruby\\lib\\yaml.rb\r\n",
      ].join
    end

    it "normalizes absolute, relative, mixed, and CR-tailed paths" do
      expect(loaded_lib_files).to eq(
        ["elkrb.rb", "elkrb/cli.rb", "elkrb/version.rb"],
      )
    end
  end

  it "requires only files that actually exist" do
    missing = requires.reject do |r|
      # "elkrb" itself is a gem-style require resolved by the load path,
      # not a bare relative file -- everything else must be a real file
      # under lib/ so a typo in this list fails loudly instead of quietly
      # requiring nothing.
      r == "elkrb" || File.exist?(File.join(repo_root, "lib", "#{r}.rb"))
    end

    expect(missing).to eq([])
  end
end
