# Filler Line Fix & Verbose Mode Implementation

**Created**: 2024-10-22 14:34:00 UTC  
**Last Updated**: 2024-10-22 14:34:00 UTC
**Issue**: Filler lines not working correctly for fixture test files
**Root Cause**: Naive line-by-line diff algorithm was misaligning changes

## Problem Analysis

### Original Issue
The fixture files showed:
```
file_a: Line1, Line2, Line3, Line4, Line5
file_b: Line1, Line2', Line3, Line6, Line4, Line5
```

The naive algorithm was producing:
```
EQUAL(1), MODIFY(2→2'), EQUAL(3), MODIFY(4→6), MODIFY(5→4), INSERT(5)
```

This was treating lines 4-5 as modifications instead of recognizing that Line 6 is an insertion.

### Expected Behavior
With proper LCS-based diff, we should get:
```
EQUAL(1), MODIFY(2→2'), EQUAL(3), INSERT(6), EQUAL(4-5)
```

This creates a **filler line on left buffer at position 4**, aligning the diff properly.

## Solution Implemented

### 1. Added Verbose Mode

**Files Modified**:
- `c-diff-core/diff_core.h` - Added `diff_core_set_verbose()` and `diff_core_print_render_plan()`
- `c-diff-core/diff_core.c` - Implemented verbose output with:
  - Input lines display
  - LCS table visualization
  - Diff operations list
  - Render plan details (line metadata, char highlights, filler flags)
- `lua/vscode-diff/init.lua` - Exposed `set_verbose()` and `print_render_plan()` to Lua
- `tests/e2e_test.lua` - Added `-v` / `--verbose` flag support

**Usage**:
```bash
nvim --headless -c "luafile tests/e2e_test.lua" -- -v
```

### 2. Replaced Naive Diff with LCS-Based Line Diff

**Algorithm Change**:

**Before** (Naive):
```c
while (i < count_a || j < count_b) {
    if (lines_equal(a[i], b[j])) {
        // EQUAL
    } else if (both_have_content) {
        // MODIFY (wrong!)
    } else { ... }
}
```

**After** (LCS):
```c
// 1. Build DP table: lcs[i][j] = length of LCS
for (int i = 1; i <= count_a; i++) {
    for (int j = 1; j <= count_b; j++) {
        if (lines_equal(a[i-1], b[j-1])) {
            lcs[i][j] = lcs[i-1][j-1] + 1;
        } else {
            lcs[i][j] = max(lcs[i-1][j], lcs[i][j-1]);
        }
    }
}

// 2. Backtrack to produce operations
while (i > 0 || j > 0) {
    if (lines_equal(a[i-1], b[j-1])) {
        // EQUAL - group consecutive
    } else if (lcs[i][j] == lcs[i-1][j-1]) {
        // MODIFY - both lines changed
    } else if (lcs[i][j] == lcs[i][j-1]) {
        // INSERT - b has extra line
    } else {
        // DELETE - a has extra line
    }
}
```

## Test Results

### Test 1: Pure Deletion
```
Input A: ["line1", "line2", "line3"]
Input B: ["line1", "line3"]

Operations:
  EQUAL(line1), DELETE(line2), EQUAL(line3)

Result:
  Left: 3 lines (real)
  Right: 2 real + 1 FILLER = 3 lines ✅
  Filler at Right[2] aligns with deleted line2
```

### Test 2: Pure Insertion
```
Input A: ["line1", "line3"]
Input B: ["line1", "line2", "line3"]

Operations:
  EQUAL(line1), INSERT(line2), EQUAL(line3)

Result:
  Left: 2 real + 1 FILLER = 3 lines ✅
  Right: 3 lines (real)
  Filler at Left[2] aligns with inserted line2
```

### Test 3: Fixture Files (The Original Problem)
```
Input A (5 lines):
  [1] Line 1: This is the first line
  [2] Line 2: This is the second line
  [3] Line 3: This is the third line
  [4] Line 4: This is the fourth line
  [5] Line 5: This is the fifth line

Input B (6 lines):
  [1] Line 1: This is the first line
  [2] Line 2: This line has been modified
  [3] Line 3: This is the third line
  [4] Line 6: This is a new line          ← NEW
  [5] Line 4: This is the fourth line
  [6] Line 5: This is the fifth line

Operations:
  [0] EQUAL(orig[0:1], mod[0:1])          Line 1
  [1] MODIFY(orig[1:1], mod[1:1])         Line 2
  [2] EQUAL(orig[2:1], mod[2:1])          Line 3
  [3] INSERT(orig[3:0], mod[3:1])         Line 6 ← FILLER ON LEFT
  [4] EQUAL(orig[3:2], mod[4:2])          Lines 4-5

Result:
  Left: Lines 1,2,3,FILLER,4,5 (6 total) ✅
  Right: Lines 1,2',3,6,4,5 (6 total) ✅
  
Perfect alignment! Line 4 on left is a filler, matching Line 6 on right.
```

## Verification

All tests pass:
```bash
$ nvim --headless -c "luafile tests/test_filler.lua" -- -v
✓ Pure Deletion: Filler on right
✓ Pure Insertion: Filler on left

$ nvim --headless -c "luafile tests/e2e_test.lua" -- -v
✓ Fixture test: Correct INSERT operation, filler on left at position 4
```

## Files Modified

1. **c-diff-core/diff_core.h**
   - Added `diff_core_set_verbose(bool enabled)`
   - Added `diff_core_print_render_plan(const RenderPlan* plan)`

2. **c-diff-core/diff_core.c**
   - Added global `g_verbose` flag
   - Implemented verbose debug output
   - **Replaced naive line diff with LCS-based algorithm** (critical fix)
   - Added LCS table visualization

3. **lua/vscode-diff/init.lua**
   - Added `M.set_verbose(enabled)`
   - Added `M.print_render_plan(c_plan)`
   - Updated FFI declarations

4. **tests/e2e_test.lua**
   - Added `-v` / `--verbose` flag parsing
   - Calls `diff.set_verbose(true)` when flag present

5. **tests/test_filler.lua** (NEW)
   - Dedicated filler line test cases
   - Tests pure deletion, pure insertion, and complex scenarios

## Summary

✅ **Filler lines now work correctly**
✅ **Verbose mode added for debugging**
✅ **LCS-based line diff produces optimal alignment**
✅ **All tests pass**

The key insight was that the naive algorithm couldn't distinguish between:
- "Line was modified" (MODIFY)
- "Line was deleted and different line appeared" (DELETE + INSERT)

The LCS algorithm solves this by finding the longest common subsequence, which naturally produces the minimal diff with proper INSERT/DELETE operations that trigger filler line generation.

## Usage Example

```bash
# Run E2E tests with verbose output
nvim --headless -c "luafile tests/e2e_test.lua" -- -v

# Run filler line tests with verbose output
nvim --headless -c "luafile tests/test_filler.lua" -- -v

# Use in plugin (from Lua)
local diff = require("vscode-diff")
diff.set_verbose(true)  -- Enable debug output
local plan = diff.compute_diff(lines_a, lines_b)
diff.print_render_plan(plan)  -- Print plan details
```

The verbose output shows:
- Input lines
- LCS table (visualized)
- Diff operations with types and ranges
- Complete render plan with filler flags, line types, character highlights
