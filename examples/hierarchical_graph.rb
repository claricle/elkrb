#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "elkrb"

# Hierarchical graph layout example
# This demonstrates nested graphs with parent-child relationships

# Create a hierarchical graph with nested nodes
graph = Elkrb::Graph.new(
  id: "root",
  children: [
    {
      id: "parent1",
      width: 400,
      height: 300,
      children: [
        { id: "p1_child1", width: 80, height: 40 },
