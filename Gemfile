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
