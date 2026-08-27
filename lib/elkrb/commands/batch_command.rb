# frozen_string_literal: true

require "fileutils"

module Elkrb
  module Commands
    # Command for processing multiple graph files in batch
    # Useful for generating diagrams for entire directories of graph files
    class BatchCommand
      def initialize(directory, options)
        @directory = directory
        @options = options
      end

      def run
        unless Dir.exist?(@directory)
          raise ArgumentError,
                "Directory not found: #{@directory}"
        end

        # Find all graph files
        pattern = File.join(@directory, "*.{json,yml,yaml,elkt}")
        files = Dir.glob(pattern, File::FNM_EXTGLOB)

        if files.empty?
          puts "No graph files found in #{@directory}"
          return
        end

        # Create output directory
        FileUtils.mkdir_p(@options[:output_dir])

        # Process each file
        success_count = 0
        error_count = 0

        files.each do |file|
          process_file(file)
          success_count += 1
        rescue StandardError => e
          error_count += 1
          warn "⚠ Error processing #{file}: #{e.message}"
        end

        # Summary
        puts ""
        puts "✓ Processed #{success_count} file(s) → #{@options[:output_dir]}"
        puts "⚠ #{error_count} error(s)" if error_count.positive?

        fail_on_errors(error_count, files.size)
      end

      private

      # The summary alone would let a batch that failed on every file still
      # exit 0, so a non-empty error count has to reach the caller.
      def fail_on_errors(error_count, total)
        return unless error_count.positive?

        require_relative "../errors"
        raise Elkrb::Error, "#{error_count} of #{total} file(s) failed"
      end

      def process_file(file)
        basename = File.basename(file, File.extname(file))
        output_file = File.join(@options[:output_dir],
                                "#{basename}.#{@options[:format]}")

        # Use DiagramCommand for each file
        opts = @options.merge(output: output_file)

        require_relative "diagram_command"
        DiagramCommand.new(file, opts).run
      end
    end
  end
end
