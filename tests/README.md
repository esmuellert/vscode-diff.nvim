# Test Suite

Integration tests for codediff.nvim using an in-tree, self-contained test framework
(`tests/framework/`) that implements the familiar `describe/it/before_each/after_each/assert.*`
API in pure Lua + Neovim built-ins. No external test dependencies are required.

## Test Coverage

### ✅ FFI Integration (ffi_integration_spec.lua)
C ↔ Lua boundary validation:
- Data structure conversion
- Memory management (no leaks)
- Edge cases (empty diffs, large files)

**10 tests**

### ✅ Git Integration (git_integration_spec.lua)
Git operations and async handling:
- Repository detection
- Async callbacks
- Error handling for invalid revisions
- Path calculation
- LRU cache validation

**9 tests**

### ✅ Installer (installer_spec.lua)
Automatic binary installation and version management:
- Module API validation
- VERSION loading from version.lua
- Library path construction
- Version detection from filenames
- Update necessity logic
- Platform-specific extension handling

**10 tests**

### ✅ Auto-scroll (autoscroll_spec.lua)
Diff view scrolling behavior:
- Scroll to first change
- Window centering
- Scroll sync activation

**5 tests**

### ✅ Semantic Tokens (render/semantic_tokens_spec.lua)
LSP integration and rendering:
- Module compatibility checks
- Virtual file URL handling
- Namespace management

**12 tests**

## Running Tests

### All tests:
```bash
./tests/run_tests.sh          # or: make test-lua
```

Spec files are auto-discovered under `tests/`, so a new `*_spec.lua` is picked
up with no runner changes.

### Individual spec:
```bash
nvim --headless --noplugin -u tests/init.lua \
  -c "lua require('tests.framework').run_and_exit('tests/core/ffi_integration_spec.lua')"
```

### How the suite runs

Each spec file gets its own child `nvim --headless` process, so specs stay
isolated from one another. `tests/framework/supervisor.lua` runs those children
concurrently from a single parent Neovim, which cuts the suite from ~150s to
~35s on a 4-core machine.

Children never share the parent's stdout: their output is buffered in full and
printed as one contiguous block when they exit. Letting concurrent processes
write to the same stream interleaves their output, both block-wise (stdout is
fully buffered when it isn't a tty) and line-wise (Neovim writes some messages
without a trailing newline).

Concurrency needs `vim.system()` (Neovim 0.10+). On older versions the suite
automatically falls back to running the same children one at a time, producing
the same output, just slower.

| Env var | Default | Purpose |
| --- | --- | --- |
| `CODEDIFF_TEST_JOBS` | 2x CPUs, capped at 16 | Concurrent spec workers. `1` forces sequential. |
| `CODEDIFF_TEST_TIMEOUT` | `300000` | Per-spec timeout in ms; guards against a hung spec stalling CI. |
| `NO_COLOR` / `CODEDIFF_TEST_NO_COLOR` | unset | Disable ANSI colors. |

## Test Philosophy

Focus on **integration points** that C tests cannot validate:
- FFI boundary integrity
- Lua async operations
- System integration (git)
- UI behavior (scrolling, rendering)

## What's NOT Covered

❌ **Diff algorithm** - Validated by C tests in `c-diff-core/tests/` (3,490 lines)
❌ **Visual correctness** - Manual testing required
