# Proposed Changes: Header Include Pattern Refactoring

## Problem Statement

The current libvscode-diff implementation uses `#include "../include/header.h"` in source files, which is:
- Not an industry standard pattern
- Problematic for IDE tooling
- Inconsistent (some files already use the correct pattern)
- Fragile if directory structure changes

## Current State

### Files Using `../include/` Pattern (21 files)

**Source Files (11):**
1. src/char_level.c
2. src/diff_api.c
3. src/line_level.c
4. src/myers.c
5. src/optimize.c
6. src/print_utils.c
7. src/range_mapping.c
8. src/render_plan.c
9. src/sequence.c
10. src/string_hash_map.c
11. src/utils.c

**Test Files (10):**
1. tests/test_char_boundary_categories.c
2. tests/test_char_level.c
3. tests/test_compute_diff.c
4. tests/test_dp_algorithm.c
5. tests/test_line_boundary_scoring.c
6. tests/test_line_optimization.c
7. tests/test_myers.c
8. tests/test_range_mapping.c
9. tests/test_render_plan.c
10. tests/test_sequence.c

**Files Already Using Correct Pattern (2):**
- default_lines_diff_computer.c (uses `include/`)
- diff_tool.c (uses `include/`)

### Current CMake Configuration
The CMakeLists.txt already properly configures include directories:
```cmake
target_include_directories(vscode_diff
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        $<$<BOOL:${USE_BUNDLED_UTF8PROC}>:${UTF8PROC_INCLUDE}>
)
```

This is correct! The problem is only in the source files.

## Proposed Solution: Option 1 (RECOMMENDED - Minimal Change)

### Change Description
Remove `../include/` prefix from all include statements, relying on CMake's configured include paths.

**Before:**
```c
#include "../include/myers.h"
#include "../include/sequence.h"
#include "../include/types.h"
```

**After:**
```c
#include "myers.h"
#include "sequence.h"
#include "types.h"
```

### Files to Modify
- 21 C source/test files (simple search-and-replace of `../include/` → ``)

### Changes Required

1. **Source Files (11 files)**: Replace all `#include "../include/` with `#include "`
2. **Test Files (10 files)**: Same replacement
3. **No CMakeLists.txt changes needed** (already correct)
4. **No directory structure changes**
5. **No header file modifications**

### Impact
- ✅ Minimal changes (only include statements)
- ✅ No build system modifications
- ✅ No directory reorganization
- ✅ Same binary output
- ✅ All tests pass identically
- ✅ Consistent with existing files
- ✅ Follows industry standards

### Example Changes

**src/myers.c (lines 26-28):**
```diff
-#include "../include/myers.h"
-#include "../include/sequence.h"
-#include "../include/string_hash_map.h"
+#include "myers.h"
+#include "sequence.h"
+#include "string_hash_map.h"
```

**tests/test_myers.c (lines 1-2):**
```diff
-#include "../include/types.h"
-#include "../include/myers.h"
+#include "types.h"
+#include "myers.h"
```

## Alternative Solution: Option 2 (More Robust, Requires Restructuring)

### Change Description
Use namespaced includes with a dedicated project directory.

**New Directory Structure:**
```
libvscode-diff/
  include/
    libvscode_diff/          # NEW namespace directory
      char_level.h
      myers.h
      sequence.h
      types.h
      ... (all headers)
  src/
    myers.c
    ... (unchanged)
```

**In Source Files:**
```c
#include "libvscode_diff/myers.h"
#include "libvscode_diff/sequence.h"
#include "libvscode_diff/types.h"
```

### Changes Required
1. Create `include/libvscode_diff/` directory
2. Move all headers from `include/` to `include/libvscode_diff/`
3. Update all include statements (21 files)
4. Update CMakeLists.txt (minor)
5. Update generated build scripts

### Impact
- ✅ Prevents header name collisions
- ✅ Professional library structure
- ✅ Better for standalone library use
- ⚠️ More extensive changes required
- ⚠️ Potential external dependencies if others use headers

## Comparison

| Aspect | Option 1 (Minimal) | Option 2 (Namespaced) |
|--------|-------------------|----------------------|
| Files to change | 21 | 21 + CMake + scripts |
| Directory changes | None | Move headers |
| CMake changes | None | Minor update |
| External impact | None | Breaks external users |
| Industry practice | ✅ Standard | ✅ Best for libraries |
| Effort | Low | Medium |
| Risk | Minimal | Low-Medium |

## Recommendation

**Use Option 1** because:
1. Minimal changes (only source files)
2. No directory reorganization
3. No build system changes
4. Matches industry standards
5. Consistent with 2 files already following this pattern
6. Lower risk of unintended side effects

## Validation Plan

After making changes:

1. **Build Test:**
   ```bash
   cmake -B build
   cmake --build build
   ```

2. **Test Execution:**
   ```bash
   cd build/libvscode-diff
   ctest
   ```

3. **Standalone Build Scripts:**
   ```bash
   ./build.sh  # Unix/macOS
   ./build.cmd  # Windows
   ```

4. **Binary Comparison:**
   - Verify shared library loads correctly
   - Check function exports unchanged
   - Validate Lua FFI integration

5. **IDE Testing:**
   - Verify code completion works
   - Check "Go to definition" functionality
   - Ensure no include errors

## Timeline Estimate

- Research & Planning: ✅ Complete
- Implementation: ~30 minutes (simple search-and-replace + testing)
- Validation: ~30 minutes (build + test on multiple platforms)
- **Total: ~1 hour**

## Next Steps

1. Get approval for Option 1 (recommended) or Option 2
2. Create implementation branch
3. Make changes to all 21 files
4. Build and test on all platforms
5. Update documentation if needed
6. Submit PR with detailed testing results

## Questions for Stakeholders

1. Is Option 1 (minimal change) acceptable?
2. Do we need to consider external users of the headers?
3. Are there any IDE-specific requirements we should test?
4. Should we update any documentation to reflect the change?

---

## Appendix: Industry Examples

### SQLite
```c
// In src/analyze.c
#include "sqliteInt.h"  // Not "../include/sqliteInt.h"
```

### Redis  
```c
// In src/cluster.c
#include "server.h"     // Not "../include/server.h"
```

### libuv
```c
// In src/unix/core.c
#include "uv.h"         // Not "../include/uv.h"
#include "internal.h"   // Not "../include/internal.h"
```

All major C projects follow the pattern of using CMake/build system managed include paths rather than relative paths in source code.
