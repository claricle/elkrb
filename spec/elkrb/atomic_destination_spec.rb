# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../lib/elkrb/atomic_destination"

RSpec.describe "atomic destination replacement" do
  subject(:atomic_destination) { Elkrb.const_get(:AtomicDestination) }

  let(:directory) { Dir.mktmpdir }
  let(:destination) { File.join(directory, "result.txt") }

  before { File.write(destination, "original") }

  after { FileUtils.remove_entry(directory) }

  it "preserves the destination when generation fails after a partial write" do
    expect do
      atomic_destination.generate(destination) do |scratch|
        File.write(scratch, "partial")
        raise IOError, "writer stopped"
      end
    end.to raise_error(IOError, "writer stopped")

    expect(File.read(destination)).to eq("original")
    expect(Dir.children(directory)).to eq(["result.txt"])
  end

  it "replaces the destination after successful generation" do
    atomic_destination.generate(destination) do |scratch|
      File.write(scratch, "complete")
    end

    expect(File.read(destination)).to eq("complete")
    expect(Dir.children(directory)).to eq(["result.txt"])
  end

  it "preserves existing destination permissions" do
    skip "POSIX file modes are not portable to Windows" if Gem.win_platform?

    File.chmod(0o640, destination)
    atomic_destination.write(destination, "complete")

    expect(File.stat(destination).mode & 0o777).to eq(0o640)
  end

  it "uses ordinary creation permissions for a new destination" do
    skip "POSIX file modes are not portable to Windows" if Gem.win_platform?

    File.unlink(destination)
    atomic_destination.write(destination, "complete")

    expect(File.stat(destination).mode & 0o777).to eq(0o666 & ~File.umask)
  end

  it "rejects an empty generated file before replacing the destination" do
    expect do
      atomic_destination.generate(destination, require_nonempty: true) { nil }
    end.to raise_error(Elkrb::Error, /produced no output/)

    expect(File.read(destination)).to eq("original")
  end
end
