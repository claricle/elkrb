# frozen_string_literal: true

require "fileutils"
require "tempfile"

require_relative "errors"

module Elkrb
  # Commits a single-file result only after its producer completes.
  class AtomicDestination
    class << self
      def write(destination, content)
        generate(destination) { |scratch| File.binwrite(scratch, content) }
      end

      def generate(destination, require_nonempty: false, &producer)
        destination = File.path(destination)
        directory = File.dirname(destination)
        FileUtils.mkdir_p(directory)

        basename = [".elkrb-", File.extname(destination)]
        Tempfile.create(basename, directory) do |file|
          File.chmod(destination_mode(destination), file.path)
          commit(file, destination, require_nonempty, &producer)
        end
      end

      private

      def commit(file, destination, require_nonempty)
        scratch = file.path
        file.close
        result = yield scratch
        validate_output!(scratch) if require_nonempty
        File.rename(scratch, destination)
        result
      end

      def validate_output!(scratch)
        return if File.file?(scratch) && File.size(scratch).positive?

        raise Error, "Output producer reported success but produced no output"
      end

      def destination_mode(destination)
        File.stat(destination).mode & 0o777
      rescue Errno::ENOENT
        0o666 & ~File.umask
      end
    end
  end
  private_constant :AtomicDestination
end
