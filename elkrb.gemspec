# frozen_string_literal: true

require_relative "lib/elkrb/version"

Gem::Specification.new do |spec|
  spec.name = "elkrb"
  spec.version = Elkrb::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "ElkRb: Ruby implementation of Eclipse Layout Kernel (ELK)"
  spec.description = <<~HEREDOC
    Pure Ruby implementation of the Eclipse Layout Kernel (ELK) providing automatic
    layout of node-link diagrams. Supports all ELK algorithms.
  HEREDOC

  spec.homepage = "https://github.com/claricle/elkrb"
  spec.license = "BSD-2-Clause"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/claricle/elkrb"
  spec.metadata["changelog_uri"] = "https://github.com/claricle/elkrb"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "lutaml-model", "~> 0.7"
  spec.add_dependency "rbs", "~> 3.0"
  spec.add_dependency "thor", "~> 1.4"
end
