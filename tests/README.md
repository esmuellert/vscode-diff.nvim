# Test Suite

This directory contains all tests for vscode-diff.nvim.

## Structure

```
tests/
├── unit/           # Lua unit tests (specific component testing)
├── e2e/            # End-to-end tests (full diff pipeline with fixtures)
└── run_all.sh      # Master test runner
```

## Running Tests

### All Tests
```bash
make test                # Run all tests (C unit + Lua unit + E2E)
make test-verbose        # Run all tests with verbose output
```

### Specific Test Suites
```bash
make test-c              # Run C unit tests only
make test-unit           # Run Lua unit tests only
make test-e2e            # Run E2E tests only
make test-e2e-verbose    # Run E2E tests with verbose output
```

### Individual Tests
```bash
# Run a single unit test
nvim --headless -c "luafile tests/unit/test_filler.lua" -c "quit"

# Run a single E2E test case
cd tests/e2e
nvim --headless -c "luafile run_case.lua" -- fixtures/simple_insert/left.txt fixtures/simple_insert/right.txt
```

## Unit Tests

Unit tests validate specific components and behaviors:

- **test_version.lua** - Version string validation
- **test_constants.lua** - Highlight type constant values
- **test_filler.lua** - Filler line insertion logic
- **test_char_diff.lua** - Character-level diff computation
- **test_render_plan.lua** - Render plan data structure

Unit tests use **assertions** to validate expected behavior and will fail if assertions don't pass.

## E2E Tests

E2E tests run the full diff pipeline (file → diff → render plan) for human validation:

### Test Cases

Each E2E test case has its own directory under `e2e/fixtures/` with:
- `left.txt` - Original file
- `right.txt` - Modified file

Current test cases:
- **simple_insert** - Pure line insertion (filler on left)
- **simple_delete** - Pure line deletion (filler on right)
- **char_level** - Character-level changes
- **multi_change** - Multiple types of changes

### Adding New E2E Test Cases

1. Create a new directory under `e2e/fixtures/`:
   ```bash
   mkdir tests/e2e/fixtures/my_test_case
   ```

2. Add the test files:
   ```bash
   echo "original content" > tests/e2e/fixtures/my_test_case/left.txt
   echo "modified content" > tests/e2e/fixtures/my_test_case/right.txt
   ```

3. Run the test:
   ```bash
   make test-e2e
   ```

### Verbose Output

E2E tests with verbose mode (`-v`) output the complete render plan from the C core, showing:
- Line-by-line metadata
- Character highlight positions
- Filler line placement
- Highlight types

This is useful for:
- Debugging diff algorithm behavior
- Validating against VSCode diff behavior
- Understanding why certain highlights appear

## Test Output

### Unit Tests
```
═══════════════════════════════════════════════════════════════════════════
                            UNIT TEST SUITE
═══════════════════════════════════════════════════════════════════════════

Running: test_version
=== Unit Test: Version ===
✓ Version: 0.1.0
✓ Test passed

Running: test_filler
=== Unit Test: Filler Lines ===
...
✓ All filler tests passed

═══════════════════════════════════════════════════════════════════════════
✓ All 5 unit tests passed
```

### E2E Tests
```
════════════════════════════════════════════════════════════════════════════
                             E2E TEST SUITE
════════════════════════════════════════════════════════════════════════════

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TEST CASE: simple_insert
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Render Plan Summary:
  Left:  3 lines
  Right: 3 lines
  Left filler lines:  1
  Right filler lines: 0
  ...

✓ Test case completed
```

## CI/CD Integration

The test suite is designed to be CI-friendly:

```bash
# In CI pipeline
make clean
make
make test

# Exit code 0 = all tests passed
# Exit code 1 = one or more tests failed
```

## Debugging Failed Tests

1. **Run with verbose output**: `make test-verbose`
2. **Run specific test**: `nvim --headless -c "luafile tests/unit/test_name.lua" -c "quit"`
3. **Check C core output**: `./test_diff_core`
4. **Inspect E2E fixtures**: Look at the actual file contents in `e2e/fixtures/`

## Test Philosophy

- **Unit tests** validate correctness with assertions
- **E2E tests** validate behavior for human review
- **Verbose mode** shows internal algorithm state for debugging
- **Minimal fixtures** keep tests fast and easy to understand
