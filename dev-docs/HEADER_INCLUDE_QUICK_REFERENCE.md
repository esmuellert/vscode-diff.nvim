# Header Include Pattern - Quick Reference Card

## Current vs Proposed

### ❌ Current (Anti-Pattern)
```c
#include "../include/myers.h"
```
- **Used by:** No major C projects
- **Issues:** Fragile, poor IDE support, non-standard
- **Files:** 21 files using this pattern

### ✅ Proposed (Industry Standard)
```c
#include "myers.h"
```
- **Used by:** Linux, SQLite, Redis, libuv, LLVM
- **Benefits:** Standard, flexible, better IDE support
- **Change:** Remove `../include/` from 21 files

## One-Line Summary
Change `#include "../include/header.h"` → `#include "header.h"` in 21 files.

## Why Change?
1. **Non-standard** - No major C project uses `../include/`
2. **CMake ready** - Build system already configured correctly
3. **Quick fix** - 30 minutes to implement
4. **Zero risk** - No functional changes

## Impact
- ✅ **Files:** 21 (11 src + 10 tests)
- ✅ **CMake:** No changes needed
- ✅ **Structure:** No reorganization
- ✅ **Tests:** Should pass identically
- ✅ **Time:** 30 minutes

## Decision
- [ ] Approve Option 1 (minimal change) - **RECOMMENDED**
- [ ] Request Option 2 (namespaced headers)
- [ ] Reject and keep current pattern

## Documentation
See `dev-docs/` for:
- `EXECUTIVE_SUMMARY_HEADER_INCLUDES.md` - Decision guide
- `HEADER_INCLUDE_INVESTIGATION_SUMMARY.md` - Full summary
- `header-include-best-practices-research.md` - Research
- `header-include-refactoring-proposal.md` - Detailed plan
- `header-include-patterns-comparison.md` - Comparisons

---
**Status:** Research complete, awaiting approval
