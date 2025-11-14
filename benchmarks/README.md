# ElkRb Performance Benchmarks

This directory contains the performance benchmarking suite for ElkRb, comparing it against elkjs and potentially Java ELK.

## Directory Structure

```
benchmarks/
├── fixtures/
│   └── graphs.json           # Test graphs in JSON format
├── results/
│   ├── elkrb_results.json    # Raw ElkRb benchmark results
│   ├── elkrb_summary.json    # ElkRb summary with metadata
│   ├── elkjs_results.json    # Raw elkjs benchmark results (if run)
│   └── elkjs_summary.json    # elkjs summary with metadata (if run)
├── generate_test_graphs.rb   # Generates test graphs
├── elkrb_benchmark.rb         # ElkRb benchmark runner
├── elkjs_benchmark.js         # elkjs benchmark runner (requires Node.js)
├── generate_report.rb         # Generates performance report
└── README.md                  # This file
```

## Running Benchmarks

### Prerequisites

* Ruby 3.0+ with ElkRb installed
* Node.js 14+ (optional, for elkjs comparison)
* elkjs npm package (optional, install with `npm install elkjs`)

### Quick Start

Run all ElkRb benchmarks and generate report:

```bash
rake benchmark:all
```

### Individual Commands

**Generate test graphs:**
```bash
rake benchmark:generate_graphs
# or
ruby benchmarks/generate_test_graphs.rb
```

**Run ElkRb benchmarks:**
```bash
rake benchmark:elkrb
# or
ruby benchmarks/elkrb_benchmark.rb
```

**Run elkjs benchmarks** (requires Node.js and elkjs):
```bash
rake benchmark:elkjs
# or
node benchmarks/elkjs_benchmark.js
```

**Generate performance report:**
```bash
rake benchmark:report
# or
ruby benchmarks/generate_report.rb
```

## Test Graphs

The benchmark suite uses four test graphs of varying complexity:

1. **Small Simple** (10 nodes, 15 edges)
   - Simple graph for basic performance testing
   - Fast execution, ideal for algorithm correctness verification

2. **Medium Hierarchical** (50 nodes, 75 edges, 3 levels)
   - Hierarchical structure with nested containers
   - Tests handling of parent-child relationships

3. **Large Complex** (200 nodes, 400 edges)
   - Large flat graph with many nodes
   - Tests scalability of algorithms

4. **Dense Network** (100 nodes, 500 edges)
   - Dense connectivity between nodes
   - Stresses edge routing and overlap prevention

## Benchmark Methodology

* **Iterations**: Each algorithm runs 10 times with a warm-up run
* **Timing**: Average execution time in milliseconds
* **Timeout**: 5 seconds per algorithm to prevent hangs
* **Error Handling**: Algorithms that fail are marked with error messages
* **Consistency**: Same test graphs used across all implementations

## Performance Metrics

The benchmarks collect:

* **Average Time**: Mean execution time across 10 runs
* **Min/Max Time**: Best and worst execution times
* **Memory Usage**: Memory delta during execution (ElkRb only)
* **Errors**: Stack overflows, timeouts, or other failures

## Algorithms Benchmarked

* `layered` - Hierarchical layered layout
* `force` - Force-directed layout
* `stress` - Stress minimization
* `box` - Simple box layout
* `random` - Random positioning
* `fixed` - Fixed node positions
* `mrtree` - Tree layout
* `radial` - Radial/circular layout
* `rectpacking` - Rectangle packing
* `disco` - Disconnected graph handling
* `topdownpacking` - Top-down packing
* `libavoid` - Orthogonal routing (libavoid-inspired)
* `vertiflex` - Vertical flex layout

Note: `sporeOverlap` and `sporeCompaction` are not yet implemented in ElkRb.

## Performance Report

The generated performance report (`docs/PERFORMANCE.adoc`) includes:

* Benchmark environment details
* Methodology description
* Performance comparison tables
* Algorithm performance analysis
* Recommendations for different use cases
* Future optimization opportunities

## Known Issues

* **Cyclic Graphs**: Some algorithms (e.g., MRTree) don't handle cyclic graphs well
* **Hierarchical Graphs**: Nested container support varies by algorithm
* **Timeouts**: Complex algorithms may timeout on very large graphs
* **Memory**: Ruby uses more memory than JavaScript due to interpreter overhead

## Tips for Running Benchmarks

1. **Close other applications** to ensure consistent performance
2. **Run multiple times** if you need statistical significance
3. **Adjust timeout** in `elkrb_benchmark.rb` if needed (default: 5s)
4. **Check logs** in `benchmarks/results/` for detailed data
5. **Compare carefully** - different environments may have different results

## Interpreting Results

* **< 10ms**: Fast, suitable for real-time/interactive use
* **10-50ms**: Medium speed, good for most applications
* **50-200ms**: Slower, suitable for batch processing
* **> 200ms**: Slow, consider simpler algorithms or optimization
* **Timeout**: Algorithm doesn't scale well for this graph size

## Contributing

To add new benchmark graphs:

1. Edit `generate_test_graphs.rb`
2. Add a new graph generation method
3. Include it in `generate_all`
4. Re-run benchmarks

To benchmark against Java ELK:

1. Create `java_elk_benchmark.java` or `.sh` script
2. Output results in same JSON format
3. Update `generate_report.rb` to include Java results
4. Add rake task for Java benchmarks