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
# newer parser and move both baselines with no code change.
gem "bundler-audit", "~> 0.9.3"
gem "flay", "~> 2.14.4"
gem "flog", "~> 4.9.4"
gem "prism", "~> 1.9.0"
gem "sexp_processor", "~> 4.17.5"
# mutant 0.16 needs Ruby >= 3.3 while elkrb.gemspec's floor is 3.2.0, so an
# unguarded entry makes `bundle install` itself fail on 3.2 -- measured, not
# assumed: bundler exits 6 with "Ruby >= 3.3 is required". CI runs a Ruby x OS
# matrix over the gemspec floor, so that would be every 3.2 cell red on code
# nobody touched. Gemfile.lock is gitignored here, so a conditional dependency
# costs nothing. Compared as Gem::Version: "3.10" < "3.3" as strings.
gem "mutant-rspec", "~> 0.16.3" if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3")
gem "reek", "~> 6.5.0"
gem "simplecov", "~> 1.1", require: false
