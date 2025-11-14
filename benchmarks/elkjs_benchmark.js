#!/usr/bin/env node
// elkjs Performance Benchmark

const fs = require('fs');

// Import elkjs - we'll check if it's available
let ELK;
try {
  ELK = require('elkjs');
} catch (e) {
  console.error('ERROR: elkjs not installed. Install it with: npm install elkjs');
  process.exit(1);
}

class ElkjsBenchmark {
  constructor() {
    this.elk = new ELK();
    this.graphs = this.loadGraphs();
    this.results = {};
  }

  loadGraphs() {
    const data = fs.readFileSync('benchmarks/fixtures/graphs.json', 'utf8');
    return JSON.parse(data);
  }

  async run() {
    console.log('elkjs Performance Benchmark');
    console.log('='.repeat(60));
    console.log(`Node Version: ${process.version}`);

    try {
      const pkg = require('elkjs/package.json');
      console.log(`elkjs Version: ${pkg.version}`);
    } catch (e) {
      console.log('elkjs Version: unknown');
    }

    console.log();

    for (const [name, data] of Object.entries(this.graphs)) {
      console.log(`Graph: ${name} - ${data.description}`);
      await this.benchmarkGraph(name, data.graph);
      console.log();
    }

    this.saveResults();
  }

  async benchmarkGraph(name, graphData) {
    this.results[name] = {};

    const algorithms = [
      'layered', 'force', 'stress', 'box', 'random', 'fixed',
      'mrtree', 'radial', 'disco'
    ];

    for (const algorithm of algorithms) {
      try {
        const times = [];

        // Clone graph data for each test
        const testGraph = JSON.parse(JSON.stringify(graphData));
        testGraph.layoutOptions = { 'elk.algorithm': algorithm };

        // Warm-up run
        await this.elk.layout(testGraph);

        // Benchmark runs (10 iterations)
        for (let i = 0; i < 10; i++) {
          const testGraphCopy = JSON.parse(JSON.stringify(graphData));
          testGraphCopy.layoutOptions = { 'elk.algorithm': algorithm };

          const start = process.hrtime.bigint();
          await this.elk.layout(testGraphCopy);
          const end = process.hrtime.bigint();

          times.push(Number(end - start) / 1_000_000); // Convert to ms
        }

        const avg = times.reduce((a, b) => a + b) / times.length;
        const min = Math.min(...times);
        const max = Math.max(...times);

        this.results[name][algorithm] = { avg, min, max };

        console.log(`  ${algorithm.padEnd(20)}: ${this.formatTime(avg)}`);
      } catch (error) {
        console.log(`  ${algorithm.padEnd(20)}: ERROR - ${error.message}`);
        this.results[name][algorithm] = { error: error.message };
      }
    }
  }

  formatTime(ms) {
    if (ms < 1) return `${(ms * 1000).toFixed(2)}µs`;
    if (ms < 1000) return `${ms.toFixed(2)}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  }

  saveResults() {
    const summary = {
      timestamp: new Date().toISOString(),
      node_version: process.version,
      elkjs_version: this.getElkjsVersion(),
      results: this.results
    };

    fs.writeFileSync(
      'benchmarks/results/elkjs_results.json',
      JSON.stringify(this.results, null, 2)
    );

    fs.writeFileSync(
      'benchmarks/results/elkjs_summary.json',
      JSON.stringify(summary, null, 2)
    );

    console.log('='.repeat(60));
    console.log('Results saved to:');
    console.log('  - benchmarks/results/elkjs_results.json');
    console.log('  - benchmarks/results/elkjs_summary.json');
  }

  getElkjsVersion() {
    try {
      const pkg = require('elkjs/package.json');
      return pkg.version;
    } catch (e) {
      return 'unknown';
    }
  }
}

// Run benchmark
if (require.main === module) {
  new ElkjsBenchmark().run().catch(console.error);
}

module.exports = ElkjsBenchmark;