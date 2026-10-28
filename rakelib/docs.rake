# frozen_string_literal: true

require_relative "docs/generated_docs"

namespace :docs do
  docs_dir = File.expand_path("../docs", __dir__)

  desc "Regenerate docs/OPTIONS.adoc from Elkrb::Options::Registry"
  task :options do
    puts "wrote #{ElkrbDocs.write(docs_dir, 'OPTIONS.adoc')}"
  end

  desc "Regenerate docs/COMPATIBILITY.adoc from the elkjs goldens"
  task :compatibility do
    puts "wrote #{ElkrbDocs.write(docs_dir, 'COMPATIBILITY.adoc')}"
  end

  desc "Regenerate every generated page under docs/"
  task all: %i[options compatibility]
end
