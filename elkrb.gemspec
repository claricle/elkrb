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
  # Ruby 3.2 reached end of life on 2026-03-31, so the floor is 3.3.
  #
  # It is also what the shared CI matrix tests. metanorma/ci's
  # ruby-matrix.json lists 3.3, 3.4 and 4.0 and no 3.2, so a 3.2 floor was a
  # promise nothing verified unless this repo carried a matrix leg of its own.
  # Raising it here deletes that leg instead of maintaining it.
  #
  # The floor cannot go BELOW 3.2 whatever CI says: lutaml-model 0.8 does not
  # parse on 3.1 or older -- 66 of its files are syntax errors on 3.0 and 15
  # on 3.1. Its own gemspec understates this as >= 3.0.0.
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/claricle/elkrb"
  spec.metadata["changelog_uri"] = "https://github.com/claricle/elkrb/blob/main/CHANGELOG.adoc"
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

  # 0.8 is the floor: the layout_options setters call the instance-level
  # lutaml_register, which 0.7.x does not define.
  # Capped below 0.9 on purpose. NodeConstraints mirrors lutaml's own
  # deserialization for the legacy YAML spellings, so a minor bump can change
  # what it does. Lift the cap once the new minor is checked.
  spec.add_dependency "lutaml-model", ">= 0.8", "< 0.9"
  spec.add_dependency "rbs", "~> 3.0"
  spec.add_dependency "thor", "~> 1.4"
end
