# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../../lib/elkrb/options/registry"
require_relative "../../spec/support/golden_cases"
require_relative "options_page"
require_relative "compatibility_page"

module ElkrbDocs
  PAGES = {
    "OPTIONS.adoc" => OptionsPage,
    "COMPATIBILITY.adoc" => CompatibilityPage,
  }.freeze

  # `rake docs:*` and spec/docs_spec.rb both render through here, so the
  # pages the spec checks are the pages the tasks write.
  def self.write(dir, file)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, file)
    File.write(path, PAGES.fetch(file).render)
    path
  end
end
