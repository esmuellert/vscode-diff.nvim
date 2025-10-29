# render.lua Evolution: From ef54a877 to Current Implementation

**Date:** October 29, 2025  
**Base Commit:** ef54a877 (Fix major mismatch between VSCode)  
**Focus:** Filler line calculation algorithm evolution

---

## Table of Contents

1. [Overview](#overview)
2. [Initial State (ef54a877)](#initial-state-ef54a877)
3. [Problem Discovery](#problem-discovery)
4. [Solution Attempts](#solution-attempts)
5. [Current Implementation](#current-implementation)
6. [Known Issues](#known-issues)
7. [VSCode Reference Implementation](#vscode-reference-implementation)
8. [Data Structure Conventions](#data-structure-conventions)

---

## Overview

This document tracks the evolution of filler line calculation in `render.lua`, focusing on the attempts to match VSCode's diff editor behavior for side-by-side view alignment.

**Key Challenge:** Determining the correct position (before vs after a line) to insert filler lines for proper vertical alignment between the original and modified editors.

---

## Initial State (ef54a877)

### Rendering Algorithm (3 Steps)

The initial implementation after commit ef54a877 used a simplified 3-step algorithm:

#### Step 1: Line-Level Highlights
```lua
-- Apply light background to entire changed line ranges
apply_line_highlights(bufnr, line_range, "VscodeDiffLineDelete")
apply_line_highlights(bufnr, line_range, "VscodeDiffLineInsert")
```

#### Step 2: Character-Level Highlights
```lua
-- Apply dark background to specific changed text from inner changes
-- Skips empty ranges and line-ending-only changes
apply_char_highlight(bufnr, char_range, "VscodeDiffCharDelete", lines)
```

#### Step 3: Filler Lines (Simple Empty Range Detection)
```lua
-- For each inner change:
if is_empty_range(original) and not is_empty_range(modified) then
  -- Insertion: add fillers to original
  insert_filler_lines(original_bufnr, after_line = original.start_line - 1, count)
elseif is_empty_range(modified) and not is_empty_range(original) then
  -- Deletion: add fillers to modified
  insert_filler_lines(modified_bufnr, after_line = modified.start_line - 1, count)
end
```

**Simplification Rationale:**
- Neovim uses fixed-height grid (no pixel calculations needed)
- No line wrapping in diff buffers
- Avoid VSCode's complex `emitAlignment` state machine

### Problem with Simple Approach

The simple empty-range detection failed for:
1. **Multi-line expansions** (e.g., single line → multiple lines)
2. **Inline insertions** that should place fillers differently based on position
3. **Mixed cases** where line count differs but neither side is empty

**Example Issue:**
- Line 1230: Mid-line insertion expanding to 16 lines
- Simple algorithm: Places fillers incorrectly
- Expected: Fillers AFTER line 1230
- Actual: No fillers added (neither side empty)

---

## Problem Discovery

### Test Case Analysis

Testing with `a.ps1` and `b.ps1` revealed specific misalignment issues:

| Line | Type | Expected Filler Position | Issue |
|------|------|--------------------------|-------|
| 1216 | Leading insertion (col=1, empty orig) | BEFORE line 1216 | ✓ Working |
| 35 | End-of-line expansion (col=50) | AFTER line 35 | ✗ Placed before |
| 1230 | Mid-line expansion (col=11, 0→16 lines) | AFTER line 1230 | ✗ No fillers |
| 1232 | Multi-line expansion (1→2 lines) | BEFORE line 1232 | ? Uncertain |
| 1566-1570 | Multi-line expansion (4→44 lines) | AFTER line 1570 | ✗ Placed after 1566 |

### Algorithm Output Analysis

From `node vscode-diff.mjs`:
```
[4] Lines 1216-1249 -> Lines 1219-1269 (36 inner changes)
     Inner: L1216:C1-L1216:C1 -> L1219:C1-L1222:C5    # 0→3 lines
     Inner: L1230:C11-L1230:C24 -> L1236:C15-L1252:C28 # 0→16 lines
     Inner: L1231:C5-L1232:C1 -> L1253:C5-L1255:C5     # 1→2 lines
```

**Key Insight:** The algorithm needs to handle:
- Empty ranges (0 lines)
- Single-line ranges (same start/end line)
- Multi-line ranges (different start/end lines)
- Position within line (column 1 vs mid-line)

---

## Solution Attempts

### Attempt 1: Simple Line Count Difference

```lua
-- For each inner change:
local orig_line_count = inner.original.end_line - inner.original.start_line
local mod_line_count = inner.modified.end_line - inner.modified.start_line
local line_diff = mod_line_count - orig_line_count

if line_diff > 0 then
  insert_filler(original_bufnr, after_line = inner.original.end_line, count = line_diff)
elseif line_diff < 0 then
  insert_filler(modified_bufnr, after_line = inner.modified.end_line, count = -line_diff)
end
```

**Result:** Added too many fillers (64 left, 9 right)
- Added fillers for every inner change including 0→0 line changes (column-only changes)

### Attempt 2: Skip Single-Line to Single-Line

```lua
-- Skip if both sides are single-line
if orig_line_count == 0 and mod_line_count == 0 then
  goto continue
end
-- ... then calculate fillers
```

**Result:** Still incorrect positioning
- Line 35 still had fillers before it instead of after

### Attempt 3: Position Based on Empty vs Non-Empty

```lua
if line_diff > 0 then
  local after_line
  if orig_line_count == 0 then
    -- Empty original: BEFORE the line
    after_line = inner.original.start_line - 1
  else
    -- Non-empty original: AFTER the line
    after_line = inner.original.start_line
  end
  insert_filler(original_bufnr, after_line, line_diff)
end
```

**Result:** Line 35 still placed fillers before (at line 34)
- Used `end_line - 1` incorrectly

### Attempt 4: Use end_line Directly

Discovered that ranges are **exclusive** at mapping level but **inclusive** at inner change level.

```lua
-- For mapping ranges: Lines 35-36 means line 35 only (end=36 is exclusive)
-- For inner changes: L35:C50-L35:C52 has end_line=35 (inclusive)
```

Changed to use `end_line` directly:
```lua
after_line = inner.original.end_line  -- Not end_line - 1
```

**Result:** Line 35 placed fillers after line 35 ✓
- But broke line 1216 (now AFTER instead of BEFORE)

### Attempt 5: VSCode Alignment-Based Approach

Studied VSCode's `diffEditorViewZones.ts` and implemented alignment creation:

```lua
-- Create alignments at specific points based on inner changes
if inner.original.start_col > 1 and inner.modified.start_col > 1 then
  -- Unmodified text BEFORE the change
  emit_alignment(inner.original.start_line, inner.modified.start_line)
end

if inner.original.end_col <= line_length then
  -- Unmodified text AFTER the change
  emit_alignment(inner.original.end_line, inner.modified.end_line)
end

-- Then convert alignments to fillers
for alignment in alignments do
  after_line = alignment.orig_end - 1
  insert_filler(bufnr, after_line, count)
end
```

**VSCode Reference:**
```typescript
// diffEditorViewZones.ts line 489-498
if (i.originalRange.startColumn > 1 && i.modifiedRange.startColumn > 1) {
  emitAlignment(i.originalRange.startLineNumber, i.modifiedRange.startLineNumber);
}
if (i.originalRange.endColumn < maxColumn) {
  emitAlignment(i.originalRange.endLineNumber, i.modifiedRange.endLineNumber);
}
```

**Result:** Complex but still inconsistent
- Line 35 worked ✓
- Line 1216 worked ✓
- But line 1232 still had issues

---

## Current Implementation

The current implementation in `render.lua` uses the **alignment-based approach** from VSCode:

### Algorithm (Step-by-Step)

#### Input
- `mapping`: A line range mapping with `inner_changes`
- `original_lines`: Array of original file lines
- `modified_lines`: Array of modified file lines

#### Processing

1. **Initialize Alignment Tracking**
   ```lua
   local alignments = {}
   local last_orig_line = mapping.original.start_line
   local last_mod_line = mapping.modified.start_line
   ```

2. **Define emit_alignment Function**
   ```lua
   local function emit_alignment(orig_line_exclusive, mod_line_exclusive)
     -- Create an alignment segment from last position to current
     local orig_range_len = orig_line_exclusive - last_orig_line
     local mod_range_len = mod_line_exclusive - last_mod_line
     
     if orig_range_len > 0 or mod_range_len > 0 then
       table.insert(alignments, {
         orig_end = orig_line_exclusive,
         mod_end = mod_line_exclusive,
         orig_len = orig_range_len,
         mod_len = mod_range_len
       })
     end
     
     last_orig_line = orig_line_exclusive
     last_mod_line = mod_line_exclusive
   end
   ```

3. **Process Each Inner Change**
   ```lua
   for _, inner in ipairs(mapping.inner_changes) do
     -- Check if starts mid-line (unmodified text BEFORE the change)
     if inner.original.start_col > 1 and inner.modified.start_col > 1 then
       emit_alignment(inner.original.start_line, inner.modified.start_line)
     end
     
     -- Check if ends before EOL (unmodified text AFTER the change)
     local orig_line_len = #original_lines[inner.original.end_line]
     if inner.original.end_col <= orig_line_len then
       emit_alignment(inner.original.end_line, inner.modified.end_line)
     end
   end
   ```

4. **Emit Final Alignment**
   ```lua
   -- Alignment at the end of the mapping
   emit_alignment(mapping.original.end_line, mapping.modified.end_line)
   ```

5. **Convert Alignments to Fillers**
   ```lua
   for _, align in ipairs(alignments) do
     local line_diff = align.mod_len - align.orig_len
     
     if line_diff > 0 then
       -- Modified has more lines: add fillers to original
       insert_filler(original_bufnr, after_line = align.orig_end - 1, count = line_diff)
     elseif line_diff < 0 then
       -- Original has more lines: add fillers to modified
       insert_filler(modified_bufnr, after_line = align.mod_end - 1, count = -line_diff)
     end
   end
   ```

### How It Works (Example: Line 35)

**Input:**
```
Inner [3]: Orig L35:C50 - L35:C52, Mod L36:C38 - L38:C5
```

**Processing:**
1. `start_col = 50 > 1` → Create alignment at L35
2. `end_col = 52 <= 70` (line length) → Create alignment at L35
3. Alignment: `orig_end=35, mod_end=38, orig_len=0, mod_len=3`
4. `line_diff = 3 - 0 = 3`
5. Insert 3 fillers to original, `after_line = 35 - 1 = 34`

**Result:** Fillers BEFORE line 35 ✗ (Expected: AFTER line 35)

---

## Known Issues

### Issue 1: Line 35 - Fillers Before Instead of After

**Symptom:** Fillers appear before line 35 (after line 34)  
**Expected:** Fillers should appear after line 35  
**Cause:** Using `align.orig_end - 1` for all cases

**Analysis:**
The alignment is created at line 35 (end of inner change). Using `after_line = 35 - 1 = 34` places fillers before line 35. But the content expansion happens AT line 35, so fillers should be after it.

**Possible Fix:** Different positioning for mid-line changes?

### Issue 2: Line 1232 - Uncertain Correct Behavior

**Symptom:** Fillers after line 1232  
**Expected:** User says fillers should be before line 1232  
**Cause:** Unknown - need to verify against VSCode

**Analysis:**
```
Inner: L1231:C5-L1232:C1 -> L1253:C5-L1255:C5
```
This is a multi-line change (1231-1232 → 1253-1255). The `start_col=5` creates alignment at line 1231. The `end_col=1` (beginning of 1232) creates alignment at line 1232.

### Issue 3: Inconsistent Positioning Logic

**Symptom:** No clear pattern for before/after placement  
**Root Cause:** Uncertain - the alignment-based approach doesn't match VSCode exactly

**Observation:**
| Case | Start Col | End Col | Expected | Current |
|------|-----------|---------|----------|---------|
| Line 1216 | 1 | 1 | BEFORE | ? |
| Line 35 | 50 | 52 | AFTER | BEFORE |
| Line 1230 | 11 | 24 | AFTER | ? |
| Line 1232 | 5 (on L1231) | 1 (on L1232) | BEFORE | AFTER |

**Pattern Hypothesis (Unconfirmed):**
- If starts at col=1 AND empty range: BEFORE
- Otherwise: AFTER
- But this doesn't explain line 1232

---

## VSCode Reference Implementation

### Source Files

**Primary Reference:**
- File: `src/vs/editor/browser/widget/diffEditor/components/diffEditorViewZones/diffEditorViewZones.ts`
- Function: `computeRangeAlignment` (lines 443-511)
- Key Section: `innerHunkAlignment` logic (lines 489-498)

**Supporting Files:**
- `src/vs/editor/common/diff/rangeMapping.ts` - Range data structures
- `src/vs/editor/common/core/ranges/lineRange.ts` - LineRange class

### VSCode's Algorithm

```typescript
// Create alignments based on inner changes
if (innerHunkAlignment) {
  for (const i of c.innerChanges || []) {
    // Unmodified text BEFORE the change
    if (i.originalRange.startColumn > 1 && i.modifiedRange.startColumn > 1) {
      emitAlignment(i.originalRange.startLineNumber, i.modifiedRange.startLineNumber);
    }
    
    // Unmodified text AFTER the change
    const maxColumn = originalModel.getLineMaxColumn(i.originalRange.endLineNumber);
    if (i.originalRange.endColumn < maxColumn) {
      emitAlignment(i.originalRange.endLineNumber, i.modifiedRange.endLineNumber);
    }
  }
}

// Final alignment at end of mapping
emitAlignment(c.original.endLineNumberExclusive, c.modified.endLineNumberExclusive);
```

**Key Difference from Our Implementation:**
VSCode uses `endLineNumber` directly (not `endLineNumber - 1`) for alignment creation, but then uses `endLineNumberExclusive - 1` for the final `afterLineNumber` when creating view zones.

### View Zone Creation

```typescript
// diffEditorViewZones.ts lines 352-373
const delta = a.modifiedHeightInPx - a.originalHeightInPx;
if (delta > 0) {
  origViewZones.push({
    afterLineNumber: a.originalRange.endLineNumberExclusive - 1,
    heightInPx: delta,
    // ... other properties
  });
}
```

**Formula:** `afterLineNumber = endLineNumberExclusive - 1`

**In Our Terms:**
- VSCode's `endLineNumberExclusive` is the line number AFTER the range
- `endLineNumberExclusive - 1` is the LAST line IN the range
- So fillers go AFTER the last line of the range

---

## Data Structure Conventions

### Our C Code Output

**Mapping-Level Ranges (EXCLUSIVE):**
```lua
mapping.original.start_line = 35  -- First line (inclusive)
mapping.original.end_line = 36    -- EXCLUSIVE (line 36 is NOT included)
-- This represents only line 35
```

**Inner Change Ranges (INCLUSIVE):**
```lua
inner.original.start_line = 35
inner.original.end_line = 35  -- INCLUSIVE (line 35 IS included)
-- This represents line 35
```

**Why the Difference?**
- **Mappings:** Follow VSCode's `LineRange` class (exclusive end)
- **Inner Changes:** Follow VSCode's `Range` class (inclusive end for same-line ranges)

### VSCode's Range Classes

**LineRange (Mappings):**
```typescript
class LineRange {
  startLineNumber: number;        // Inclusive
  endLineNumberExclusive: number; // Exclusive
}
```

**Range (Inner Changes):**
```typescript
class Range {
  startLineNumber: number;
  startColumn: number;
  endLineNumber: number;    // Inclusive for same-line ranges
  endColumn: number;
}
```

### Conversion Rules

When using VSCode's algorithm in our code:

1. **For mapping final alignment:**
   ```lua
   emit_alignment(mapping.original.end_line, mapping.modified.end_line)
   -- end_line is already exclusive, use directly
   ```

2. **For inner change alignments:**
   ```lua
   emit_alignment(inner.original.end_line, inner.modified.end_line)
   -- end_line is INCLUSIVE for inner changes, but use directly per VSCode
   ```

3. **For calculating after_line:**
   ```lua
   after_line = alignment.orig_end - 1
   -- This converts exclusive end to the last included line
   ```

**Current Issue:** This conversion doesn't produce the expected results for all cases.

---

## Next Steps

### Investigation Needed

1. **Verify VSCode Behavior:** Open `a.ps1` and `b.ps1` in VSCode diff editor
   - Screenshot/document where fillers appear for lines 35, 1216, 1230, 1232, 1566-1570
   - Identify the actual pattern

2. **Check Inner Change Data:** Verify our C code produces correct inner change ranges
   - Compare with VSCode's JSON output
   - Ensure start_line/end_line match VSCode's expectations

3. **Test Alignment Creation:** Add debug output to track all alignments created
   - Log each `emit_alignment` call with context
   - Compare with expected VSCode behavior

### Potential Solutions

**Option 1: Different positioning based on context**
```lua
if is_leading_insertion and orig_line_count == 0 then
  after_line = align.orig_end - 1  -- BEFORE the line
else
  after_line = align.orig_end      -- AFTER the line
end
```

**Option 2: Use VSCode's exact algorithm (TypeScript → Lua port)**
- Port the entire `computeRangeAlignment` function
- Include all edge case handling
- Ensure identical behavior

**Option 3: Simplified heuristic**
```lua
-- Based on observed pattern (if confirmed):
if starts_at_col_1 and is_empty_original then
  position = "BEFORE"
else
  position = "AFTER"
end
```

---

## Conclusion

The filler line positioning algorithm has evolved through multiple iterations, attempting to match VSCode's behavior. The current alignment-based approach closely follows VSCode's logic but still produces incorrect positioning in some cases.

**Root Cause:** Uncertain - likely a subtle difference in how alignment endpoints are interpreted or how inner change ranges are structured.

**Recommendation:** Before further changes, verify the expected behavior directly against VSCode to establish ground truth for all test cases.

---

**Last Updated:** October 29, 2025  
**Status:** Work in Progress - Known Issues Exist  
**Priority:** HIGH - Affects core diff viewing experience
