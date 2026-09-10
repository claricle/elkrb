# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in omnizip.gemspec
gemspec

gem "rake"
gem "rspec"
# Pinned to a single release series: a new rubocop or plugin version can add or
# change cops, which invalidates .rubocop_todo.yml and turns CI red on code
# nobody touched. Gemfile.lock is gitignored, so these constraints are the only
# thing that makes the ratchet reproducible on a fresh checkout.
gem "rubocop", "~> 1.89.0"
gem "rubocop-performance", "~> 1.27.0"

# Quality and security tooling. Pinned for the same reason as rubocop above:
# these report against recorded baselines, and an unpinned upgrade moves the
# numbers on code nobody touched.
#
# prism and sexp_processor are pinned too, and they are the load-bearing half.
# flog and flay parse through them rather than through `parser`, they declare
# them only as `~> 1.7` and `~> 4.0`, and Gemfile.lock is gitignored here -- so
# pinning flog and flay alone still lets a fresh `bundle install` resolve a
# newer prism or sexp_processor and move both baselines with no code change.
gem "bundler-audit", "~> 0.9.3"
gem "flay", "~> 2.14.4"
gem "flog", "~> 4.9.4"
gem "prism", "~> 1.9.0"
gem "sexp_processor", "~> 4.17.5"
# Keep this guard. mutant needs 3.3 and the gemspec floor is also 3.3, so it
# changes nothing today; it speaks again the moment mutant needs a version
# above our floor.
#
# Compare as Gem::Version, never as strings. As strings "3.10" sorts below
# "3.3", which would exclude Ruby 3.10 from a 3.3+ guard.
gem "mutant-rspec", "~> 0.16.3" if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3")
gem "reek", "~> 6.5.0"
# Pinned to a patch series like the rest of this block, not `~> 1.1`. SimpleCov
# has changed filter semantics within 1.x -- SourceFile#project_filename strips
# the leading separator, so a filter written for an older minor can quietly stop
# matching -- and that is exactly the kind of drift a coverage floor hides.
gem "simplecov", "~> 1.1.1", require: false
