# Integration Tests

Focused integration tests for vscode-diff.nvim Lua layer.

## What These Tests Cover

### ✅ FFI Integration (test_ffi_integration.lua)
Tests the critical C ↔ Lua boundary:
- Data structure conversion from C to Lua
- Memory management (no leaks)
- Edge cases (empty diffs, large files)
- Return value validation

**10 tests** - Ensures FFI bindings work correctly

### ✅ Git Integration (test_git_integration.lua)
Tests git operations and async handling:
- Git repository detection
- Async callback invocation
- Error handling for invalid revisions
- Path calculation
- Multiple concurrent async calls

**8 tests** - Ensures git operations are robust

## What These Tests DON'T Cover

❌ **Algorithm correctness** - Validated by C tests in `c-diff-core/tests/` (3,490 lines)
❌ **Rendering validation** - Visual output, tested manually
❌ **Diff quality** - C layer responsibility

## Running Tests

### All tests:
```bash
./tests/run_tests.sh
```

### Individual test suites:
```bash
nvim --headless -c "luafile tests/test_ffi_integration.lua" -c "quit"
nvim --headless -c "luafile tests/test_git_integration.lua" -c "quit"
```

## Test Philosophy

These tests focus on **integration points** that C tests cannot validate:
- FFI boundary integrity
- Lua-side async operations
- System integration (git)

Total: **18 tests, ~200 lines** of focused, high-value coverage.
