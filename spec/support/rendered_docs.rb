# frozen_string_literal: true

require "tmpdir"
require_relative "../../rakelib/docs/generated_docs"

# What the docs generators render for one page, read back from a scratch
# directory so a local docs/ is never touched.
module RenderedDocs
  def rendered(file)
    Dir.mktmpdir { |dir| File.read(ElkrbDocs.write(dir, file)) }
  end
end

RSpec.configure { |config| config.include RenderedDocs }
