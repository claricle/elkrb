# frozen_string_literal: true

require "fileutils"

require_relative "../best_effort_write"

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
          # Best-effort: this notice carries no result -- there is nothing
          # left to do either way, so a dead stdout must not decide the
          # exit status here any more than it does after real work below.
          # See Elkrb::BestEffortWrite.
          BestEffortWrite.attempt do
            puts "No graph files found in #{@directory}"
          end
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

        # Best-effort: every file above is already written to output_dir.
        # This summary must not decide the exit status -- see
        # Elkrb::BestEffortWrite.
        BestEffortWrite.attempt do
          puts ""
          puts "✓ Processed #{success_count} file(s) → #{@options[:output_dir]}"
          puts "⚠ #{error_count} error(s)" if error_count.positive?
        end
      end

      private

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
