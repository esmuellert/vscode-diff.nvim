# Header Include Patterns: Current vs Proposed

## Current Pattern (Anti-Pattern)

### Directory Structure
```
libvscode-diff/
├── include/
│   ├── myers.h
│   ├── sequence.h
│   └── types.h
├── src/
│   ├── myers.c          [includes: #include "../include/myers.h"]
│   ├── sequence.c       [includes: #include "../include/sequence.h"]
│   └── ...
└── tests/
    ├── test_myers.c     [includes: #include "../include/myers.h"]
    └── ...
```

### Include Statements
```c
// In src/myers.c
#include "../include/myers.h"      // ❌ Fragile relative path
#include "../include/sequence.h"   // ❌ Breaks if moved
#include "../include/types.h"      // ❌ Not industry standard
```

### Problems
- ❌ Tight coupling to directory structure
- ❌ Breaks if files are reorganized
- ❌ Poor IDE support (IntelliSense issues)
- ❌ Not used by major C projects
- ❌ Inconsistent with 2 root-level files

---

## Proposed Pattern (Industry Standard)

### Directory Structure (Unchanged)
```
libvscode-diff/
├── include/             [Added to include path via CMake]
│   ├── myers.h
│   ├── sequence.h
│   └── types.h
├── src/
│   ├── myers.c          [includes: #include "myers.h"]
│   ├── sequence.c       [includes: #include "sequence.h"]
│   └── ...
└── tests/
    ├── test_myers.c     [includes: #include "myers.h"]
    └── ...
```

### Include Statements
```c
// In src/myers.c
#include "myers.h"      // ✅ Clean, simple
#include "sequence.h"   // ✅ CMake manages path
#include "types.h"      // ✅ Easy to relocate
```

### CMake Configuration (Already Correct!)
```cmake
target_include_directories(vscode_diff
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)
```

### Advantages
- ✅ Build system controls paths
- ✅ Flexible directory organization
- ✅ Better IDE integration
- ✅ Industry standard pattern
- ✅ Matches existing root files

---

## Comparison with Other Projects

### Pattern A: libvscode-diff (Current)
```
src/myers.c:        #include "../include/myers.h"     ❌
```

### Pattern B: SQLite
```
src/analyze.c:      #include "sqliteInt.h"            ✅
```

### Pattern C: Redis
```
src/cluster.c:      #include "server.h"               ✅
```

### Pattern D: libuv
```
src/unix/core.c:    #include "uv.h"                   ✅
```

### Pattern E: LLVM (Namespaced)
```
lib/Support/Path.cpp:  #include "llvm/Support/Path.h" ✅
```

---

## Migration Example

### File: src/myers.c

#### Before (Current)
```c
/**
 * Myers Diff Algorithms - ISequence Version
 */

#include "../include/myers.h"
#include "../include/sequence.h"
#include "../include/string_hash_map.h"
#include <stdlib.h>
#include <string.h>
```

#### After (Proposed)
```c
/**
 * Myers Diff Algorithms - ISequence Version
 */

#include "myers.h"
#include "sequence.h"
#include "string_hash_map.h"
#include <stdlib.h>
#include <string.h>
```

**Change:** Remove `../include/` prefix (10 characters)

---

## Migration Statistics

### Files to Modify
- **11 source files** in `src/`
- **10 test files** in `tests/`
- **Total: 21 files**

### Total Include Statement Changes
- Approximately **80-100 include statements**
- All follow same pattern: remove `../include/`
- Automated search-and-replace safe

### Build System Changes
- **0 files** (CMake already correct)

### Directory Structure Changes  
- **0 changes** (no files moved)

---

## Alternative: Namespaced Headers (Future Enhancement)

### Directory Structure
```
libvscode-diff/
├── include/
│   └── libvscode_diff/          # New namespace directory
│       ├── myers.h
│       ├── sequence.h
│       └── types.h
├── src/
│   ├── myers.c                  [includes: #include "libvscode_diff/myers.h"]
│   └── ...
```

### Include Statements
```c
// In src/myers.c
#include "libvscode_diff/myers.h"
#include "libvscode_diff/sequence.h"
#include "libvscode_diff/types.h"
```

### When to Use This
- ✅ If headers will be installed system-wide
- ✅ To prevent name collisions
- ✅ For public API clarity
- ⚠️ Requires more changes (moving headers)
- ⚠️ Not needed for current use case

---

## Recommendation

**Use the simple pattern (remove `../include/`):**

1. **Lowest risk** - minimal changes
2. **Standard practice** - matches industry norms
3. **Already working** - CMake configured correctly
4. **Quick migration** - simple search-and-replace
5. **Consistent** - matches existing root-level files

The namespaced approach can be considered later if the library is made standalone or installed system-wide.

---

## Implementation Checklist

### Phase 1: Preparation
- [x] Research industry best practices
- [x] Document current state
- [x] Create migration plan
- [ ] Get stakeholder approval

### Phase 2: Implementation (When Approved)
- [ ] Update all 11 source files in `src/`
- [ ] Update all 10 test files in `tests/`
- [ ] Build and verify compilation
- [ ] Run all tests
- [ ] Test standalone build scripts

### Phase 3: Validation (When Approved)
- [ ] Cross-platform build test (Linux, macOS, Windows)
- [ ] IDE integration test (VSCode, Vim)
- [ ] Lua FFI integration test
- [ ] Performance comparison (should be identical)

### Phase 4: Documentation (When Approved)
- [ ] Update BUILD_VSCODE_DIFF.md if needed
- [ ] Document the change in dev notes
- [ ] Add comment to code explaining the pattern

---

## Summary

The current `../include/` pattern is an anti-pattern that should be eliminated. The recommended fix is simple: remove the `../include/` prefix and rely on CMake's properly configured include directories. This brings the project in line with industry standards and improves maintainability.

**No code changes yet - awaiting approval per requirements.**
