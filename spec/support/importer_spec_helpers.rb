# frozen_string_literal: true

require "json"
require "stringio"

module ImporterSpecHelpers
  private

  # Importers are script entry points: they warn on stderr and call exit
  # rather than raising. Capture both streams so progress stays out of RSpec.
  def import(importer)
    stdout = $stdout
    stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    status = exit_status { importer.import_all }
    [status, $stderr.string]
  ensure
    $stdout = stdout
    $stderr = stderr
  end

  # nil means the importer ran to completion instead of exiting.
  def exit_status
    yield
    nil
  rescue SystemExit => e
    e.status
  end

  def written_ids(cwd)
    path = File.join(cwd, described_class::OUTPUT_PATH, "imported_tests.json")
    return nil unless File.exist?(path)

    JSON.parse(File.read(path)).map { |kase| kase["id"] }
  end
end
