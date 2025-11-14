# ElkRb Cross-Validation Test Suite

This directory contains the cross-validation test suite for validating ElkRb against reference implementations (elkjs and Java ELK).

## Overview

The cross-validation suite:
- Imports test cases from elkjs and Java ELK
- Runs them through ElkRb's layout engine
- Validates outputs and generates compatibility reports
- Helps ensure ElkRb maintains compatibility with reference implementations

## Directory Structure

```
spec/cross_validation/
├── README.md                           # This file
├── elkjs_test_importer.rb             # Imports test cases from elkjs
├── java_elk_test_importer.rb          # Imports test cases from Java ELK
├── validation_runner.rb                # Runs validation tests
├── generate_validation_report.rb       # Generates AsciiDoc report
├── validation_report.json              # JSON validation results
└── fixtures/
    ├── elkjs/
    │   └── imported_tests.json        # Imported elkjs test cases
    └── java_elk/
        └── imported_tests.json        # Imported Java ELK test cases
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

### Run Validation

Run cross-validation tests:
```bash
rake validate:run
```

This will:
- Load imported test cases
- Run each test through ElkRb
- Validate outputs
- Generate validation_report.json

### Generate Report

Generate AsciiDoc validation report:
```bash
rake validate:report
```

This creates `docs/VALIDATION_REPORT.adoc` with:
- Summary statistics
- Per-source compatibility rates
- Failed test details
- Recommendations

### Full Pipeline

Run the complete validation pipeline:
```bash
rake validate:all
```

This executes:
1. Import all test cases
2. Run validation
3. Generate report (optional: add `rake validate:report` after)

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

## Validation Runner

Located at: `spec/cross_validation/validation_runner.rb`

Features:
- Timeout protection (5s per test) to prevent infinite loops
- Stack overflow detection for cycle detection
- Detailed error reporting
- Progress indicators (. = pass, F = fail)
- JSON report generation

## Current Results

**Overall Pass Rate: 87.88% (29/33 tests)**

### elkjs Compatibility: 100% ✅
- All 16 elkjs test cases pass
- Full compatibility with elkjs reference implementation

### Java ELK Compatibility: 76.47%
- 13 of 17 tests pass
- 4 failing tests:
  1. `sporeOverlap` - Algorithm not yet implemented
  2. `sporeCompaction` - Algorithm not yet implemented
  3. `labels` - Label initialization issue
  4. `self_loops` - Cycle detection causing stack overflow

## Known Issues

### Missing Algorithms
- `sporeOverlap` - Not implemented
- `sporeCompaction` - Not implemented

### Implementation Issues
1. **Label Initialization**: Label model expects no arguments but receiving 1
2. **Self-Loop Detection**: Layer assignment creates infinite recursion with self-loops

## Next Steps

1. Implement missing spore algorithms
2. Fix Label model initialization
3. Add cycle detection to prevent infinite recursion in layer assignment
4. Import real test cases from elk-models repository if available
5. Add more comprehensive test coverage for edge cases

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
    bundle exec rake validate:report
```

## Contributing

When adding new features or algorithms:
1. Add corresponding test cases to importers
2. Run validation: `rake validate:all`
3. Ensure pass rate doesn't decrease
4. Update this README with any new findings

## License

Same as ElkRb main project.