# ElkRb Cross-Validation Test Suite

This directory contains the cross-validation test suite for validating ElkRb against reference implementations (elkjs and Java ELK).

## Overview

The cross-validation suite:
- Imports test cases from elkjs and Java ELK
- Runs them through ElkRb's layout engine
- Helps ensure ElkRb maintains compatibility with reference implementations

## Directory Structure

```
spec/cross_validation/
├── README.md                             # This file
├── elkjs_test_importer.rb                # Imports test cases from elkjs
├── elkjs_test_importer_spec.rb           # Its refusal guards and glob
├── java_elk_test_importer.rb             # Imports test cases from Java ELK
├── java_elk_test_importer_spec.rb        # Its refusal guard and glob
├── corpus_runner.rb                      # Runs corpus cases, writes canonical dumps
├── corpus_runner_fixture_paths_spec.rb   # What the source globs may list
├── corpus_runner_prune_spec.rb           # What a dump directory may delete
├── corpus_spec.rb                        # Asserts corpus invariants
└── fixtures/
    ├── elkjs/
    │   └── imported_tests.json          # Imported elkjs test cases
    └── java_elk/
        └── imported_tests.json          # Imported Java ELK test cases
```

## Usage

### Import Test Cases

Import test cases from elkjs:
```bash
rake validate:import_elkjs
```

Import test cases from Java ELK:
```bash
rake validate:import_java_elk
```

Import all test cases:
```bash
rake validate:import_all
```

Both importers rewrite their `imported_tests.json` wholesale. Neither will
write an empty one: if an import collects nothing, it warns and exits 1
instead of overwriting the committed fixture. `rake validate:all` stops
there, so a broken checkout aborts the pipeline rather than emptying the
corpus.

The elkjs importer reads `~/src/external/elkjs` by default. Point it
somewhere else with `ELKJS_DIR`:

```bash
ELKJS_DIR=/path/to/elkjs rake validate:import_elkjs
```

### Run Validation

Run cross-validation cases:
```bash
rake validate:run
```

This will:
- Load imported test cases
- Lay out each corpus case through ElkRb
- Write one canonical JSON file per case plus `summary.json` to the
  output directory (`tmp/corpus` for this task)

### Full Pipeline

Run the complete validation pipeline:
```bash
rake validate:all
```

This executes:
1. Import all test cases
2. Run validation

## Test Importers

### elkjs Test Importer

Located at: `spec/cross_validation/elkjs_test_importer.rb`

Imports test cases from elkjs repository at:
- `~/src/external/elkjs/test/mocha`

Generates test cases for:
- Basic layout tests
- Bug regression tests
- Algorithm-specific tests
- Option tests

### Java ELK Test Importer

Located at: `spec/cross_validation/java_elk_test_importer.rb`

Attempts to import from elk-models repository at:
- `~/src/external/elk/../elk-models`

If not found, generates sample test cases for:
- All supported algorithms
- Hierarchical graphs
- Port constraints
- Labels
- Self-loops
- Compound graphs

## Corpus Runner

Located at: `spec/cross_validation/corpus_runner.rb`

Features:
- Timeout protection (30s per case) to prevent infinite loops
- Stack overflow detection for cycle detection
- Detailed error reporting
- Writes one canonical JSON file per case plus a summary

## Current Results

47 corpus cases. 44 lay out cleanly, 3 error, none time out. All three
errors are declared in their own fixture with `"expect": "error"`, so a
healthy dump still exits 0:

- `duplicate_ids` — the graph declares the same id twice (RC4).
- `java_elk_sporeOverlap`, `java_elk_sporeCompaction` — both algorithms
  resolve and then crash on nil arithmetic inside themselves.

`corpus_spec.rb` runs the same 47 cases as examples and holds each result
to the layout invariants. Its `KNOWN_FAILURES` ledger is the list of
cases that are still pending, with the id that tracks each one.

## Adding New Test Cases

To add custom test cases:

1. Create a new importer or modify existing ones
2. Follow the test case format:
```ruby
{
  id: "unique_test_id",
  source: "test_source",
  category: "test_category",
  algorithm: "algorithm_name",
  graph: {
    id: "root",
    children: [...],
    edges: [...]
  }
}
```

3. Save to appropriate fixtures directory
4. Run validation

## Continuous Integration

Add to CI pipeline:
```bash
# In .github/workflows/test.yml or similar
- name: Run cross-validation
  run: |
    bundle exec rake validate:import_all
    bundle exec rake validate:run
```

## Contributing

When adding new features or algorithms:
1. Add corresponding test cases to importers
2. Run validation: `rake validate:all`
3. Ensure pass rate doesn't decrease
4. Update this README with any new findings

## License

Same as ElkRb main project.