# Filler Line Algorithm

This document provides a comprehensive explanation of how the filler line insertion mechanism works in vscode-diff.nvim, which replicates VSCode's advanced diff algorithm for side-by-side view alignment.

## Table of Contents

1. [Overview](#overview)
2. [Background: What are Filler Lines?](#background-what-are-filler-lines)
3. [Algorithm Architecture](#algorithm-architecture)
4. [Step-by-Step Walkthrough](#step-by-step-walkthrough)
5. [Three Alignment Scenarios](#three-alignment-scenarios)
6. [Real-World Examples](#real-world-examples)
7. [Why the OR Redundancy Check is Critical](#why-the-or-redundancy-check-is-critical)
8. [References](#references)

---

## Overview

The filler line algorithm ensures that corresponding lines in a side-by-side diff view are visually aligned, making it easy to see which lines changed, were added, or were removed. When one side has more lines than the other within a changed region, "filler lines" (blank placeholder lines) are inserted on the shorter side to maintain alignment.

This implementation precisely matches VSCode's diff rendering behavior by using the same alignment logic from VSCode's TypeScript implementation.

**Implementation Location**:
- **Our code**: `lua/vscode-diff/render.lua`, function `calculate_fillers()` (lines 283-367)
- **VSCode reference**: `src/vs/editor/browser/widget/diffEditor/features/diffEditorViewZones.ts`, function `computeRangeAlignment()` (lines 475-615)

---

## Background: What are Filler Lines?

In side-by-side diff view, filler lines are invisible placeholder lines inserted to ensure corresponding content aligns vertically across both editors.

**Example**:
```
Original (left)          Modified (right)
-----------------        ------------------
Line 10                  Line 10
Line 11                  Line 11  
Line 12                  Line 12
[FILLER]                 Line 13 (new)
[FILLER]                 Line 14 (new)
[FILLER]                 Line 15 (new)
Line 13                  Line 16
Line 14                  Line 17
```

Without fillers, line 13 in the original would appear at a different vertical position than line 16 in the modified version, making it hard to track corresponding lines.

---

## Algorithm Architecture

The algorithm operates in two phases:

### Phase 1: Create Alignments
Process each diff mapping to determine where original and modified lines should align. This produces a list of alignment points.

**Key concept**: An "alignment" defines a range of lines on both sides that should be vertically synchronized.

### Phase 2: Convert Alignments to Fillers
For each alignment where line counts differ, insert filler lines on the side with fewer lines.

```
Alignment: orig[35,36) → mod[35,39)
           ↓             ↓
         1 line        4 lines
           ↓             ↓
    Insert 3 fillers on original side
```

---

## Step-by-Step Walkthrough

### Input Data

The algorithm receives diff mappings from the C diff core, where each mapping contains:

```lua
mapping = {
  original = { start_line, end_line },    -- Line range in original file
  modified = { start_line, end_line },    -- Line range in modified file
  inner_changes = [...]                    -- Character-level changes within the mapping
}
```

**Note**: Line ranges use **exclusive end** notation: `[start, end)` means from `start` (inclusive) to `end` (exclusive).

**VSCode reference**: `DiffMapping` type in `diffEditorViewModel.ts` (lines 50-70)

---

### Phase 1: Creating Alignments

**Location**: `lua/vscode-diff/render.lua`, lines 285-339  
**VSCode reference**: `diffEditorViewZones.ts`, lines 475-615

#### Step 1.1: Initialize Tracking Variables

```lua
local alignments = {}
local last_orig_line = last_orig_line or mapping.original.start_line  
local last_mod_line = last_mod_line or mapping.modified.start_line
local first = true
```

**Purpose**:
- `alignments`: Collects all alignment points for this mapping
- `last_orig_line`, `last_mod_line`: Track the current position as we process inner changes (passed from previous mapping for global gap handling)
- `first`: VSCode's "first flag" - allows the initial alignment even if position hasn't advanced

**Why needed**: These variables track state as we iterate through inner changes, ensuring we don't create redundant or backwards alignments. State persists across mappings to handle gaps.

**VSCode reference**: Lines 538-540 in `diffEditorViewZones.ts`

#### Step 1.1.1: Handle Gap Alignment

```lua
local function handle_gap_alignment(orig_line_exclusive, mod_line_exclusive)
  local orig_gap = orig_line_exclusive - last_orig_line
  local mod_gap = mod_line_exclusive - last_mod_line
  
  if orig_gap > 0 or mod_gap > 0 then
    table.insert(alignments, {...})
    last_orig_line = orig_line_exclusive
    last_mod_line = mod_line_exclusive
  end
end

handle_gap_alignment(mapping.original.start_line, mapping.modified.start_line)
```

**Purpose**: Create alignment for any gap between the last processed line and this mapping's start (VSCode's `handleAlignmentsOutsideOfDiffs`).

**Why needed**: Without this, gaps between mappings lose alignment context, causing drift in unchanged regions.

---

#### Step 1.2: Define emit_alignment Function

```lua
local function emit_alignment(orig_line_exclusive, mod_line_exclusive)
  -- Step 1.2.1: Check if going backwards
  if orig_line_exclusive < last_orig_line or mod_line_exclusive < last_mod_line then
    return
  end
  
  -- Step 1.2.2: Check for redundancy with first flag
  if first then
    first = false
  elseif orig_line_exclusive == last_orig_line or mod_line_exclusive == last_mod_line then
    return
  end

  -- Step 1.2.3: Calculate range lengths
  local orig_range_len = orig_line_exclusive - last_orig_line
  local mod_range_len = mod_line_exclusive - last_mod_line

  -- Step 1.2.4: Create alignment if non-empty
  if orig_range_len > 0 or mod_range_len > 0 then
    table.insert(alignments, {
      orig_start = last_orig_line,
      orig_end = orig_line_exclusive,
      mod_start = last_mod_line,
      mod_end = mod_line_exclusive,
      orig_len = orig_range_len,
      mod_len = mod_range_len
    })
  end

  -- Step 1.2.5: Update tracking
  last_orig_line = orig_line_exclusive
  last_mod_line = mod_line_exclusive
end
```

**VSCode reference**: Lines 534-568 in `diffEditorViewZones.ts`

##### Step 1.2.1: Backwards Check

```lua
if orig_line_exclusive < last_orig_line or mod_line_exclusive < last_mod_line then
  return
end
```

**Purpose**: Prevent creating alignments that go backwards from our current position.

**Why**: Inner changes are processed in order. If a proposed alignment would move backwards on either side, it's invalid and must be skipped.

**VSCode reference**: Line 535 in `diffEditorViewZones.ts`

##### Step 1.2.2: Redundancy Check with First Flag

```lua
if first then
  first = false
elseif orig_line_exclusive == last_orig_line or mod_line_exclusive == last_mod_line then
  return
end
```

**Purpose**: Skip redundant alignments where neither side has advanced, but allow the very first alignment.

**Why the `first` flag is critical**:
- **Without it**: The first inner change at position `emit(start, start)` would be skipped because `start == start`, breaking alignments that need to start at the mapping beginning.
- **With it**: The first call proceeds, setting `first=false`, then subsequent redundant calls are properly skipped.

**The OR logic** (`==` on either side):
- Skips alignment if **either** the original **or** modified position hasn't advanced
- This prevents creating multiple small alignments when changes span the same original line
- Forces the algorithm to wait until **both** sides advance before creating a new alignment

**VSCode reference**: Lines 536-540 in `diffEditorViewZones.ts`
```typescript
if (first) {
  first = false;
} else if (!forceAlignment && (origLineNumberExclusive === lastOrigLineNumber || 
                                modLineNumberExclusive === lastModLineNumber)) {
  return; // Skip redundant alignment
}
```

##### Step 1.2.3: Calculate Range Lengths

```lua
local orig_range_len = orig_line_exclusive - last_orig_line
local mod_range_len = mod_line_exclusive - last_mod_line
```

**Purpose**: Determine how many lines this alignment covers on each side.

**Example**:
- `last_orig_line = 35`, `orig_line_exclusive = 36` → `orig_range_len = 1`
- `last_mod_line = 35`, `mod_line_exclusive = 39` → `mod_range_len = 4`

**VSCode reference**: Lines 542-558 in `diffEditorViewZones.ts`

##### Step 1.2.4: Create Alignment

```lua
if orig_range_len > 0 or mod_range_len > 0 then
  table.insert(alignments, {...})
end
```

**Purpose**: Only create alignment if at least one side has content (non-zero length).

**Why**: Empty alignments on both sides (0 lines → 0 lines) serve no purpose and are skipped.

**VSCode reference**: Lines 548-558 in `diffEditorViewZones.ts`

##### Step 1.2.5: Update Tracking

```lua
last_orig_line = orig_line_exclusive
last_mod_line = mod_line_exclusive
```

**Purpose**: Move our current position forward to the end of this alignment.

**Impact**: Subsequent `emit_alignment` calls will measure from this new position.

**VSCode reference**: Lines 567-568 in `diffEditorViewZones.ts`

---

#### Step 1.3: Process Inner Changes

Inner changes represent character-level modifications within the mapping. Each inner change may trigger alignment creation to preserve visual correspondence of unchanged portions.

```lua
for _, inner in ipairs(mapping.inner_changes) do
  -- Process each inner change
end
```

**VSCode reference**: Lines 581-609 in `diffEditorViewZones.ts`

There are **two alignment opportunities** per inner change:

##### Opportunity 1: BEFORE Alignment (lines 324-326)

```lua
if inner.original.start_col > 1 and inner.modified.start_col > 1 then
  emit_alignment(inner.original.start_line, inner.modified.start_line)
end
```

**Triggers when**: The change starts after column 1 on both sides.

**Purpose**: Align the unchanged text that appears **before** the change on the line.

**Example**:
```
Original: "    VERTEX MODE (Full Enterprise Setup with -Vertex)"
                                                          ^
                                                      Column 53 (change starts here)
Modified: "    VERTEX MODE (Full Enterprise Setup with -Vertex):"
                                                          ^
                                                      Column 53 (colon added)
```

The unchanged prefix (columns 1-52) should be aligned. This creates `emit(14, 14)` to ensure the prefix aligns before processing the change.

**Why the condition checks both sides**: If either side starts at column 1, there's no unchanged prefix to align.

**VSCode reference**: Lines 585-591 in `diffEditorViewZones.ts`

##### Opportunity 2: AFTER Alignment (lines 330-335)

```lua
local orig_line_len = original_lines[inner.original.end_line] and 
                      #original_lines[inner.original.end_line] or 0
if inner.original.end_col <= orig_line_len then
  emit_alignment(inner.original.end_line, inner.modified.end_line)
end
```

**Triggers when**: The change ends before the end of the original line.

**Purpose**: Align the unchanged text that appears **after** the change on the line.

**Example**:
```
Original Line 1216: "#region Step 5: Initialize Development Environment"
                    ^
                Column 1 (change starts)

Modified Lines 1219-1222: (4 new lines inserted)
                          ^
                      Column 1 (insertion point)
```

The change ends at column 1 (before the 52-character line ends), so there's unchanged text after. This creates `emit(1216, 1222)` to align after the insertion.

**Why check `end_col <= orig_line_len`**: If the change extends to or past the line end, there's no unchanged suffix to align.

**VSCode reference**: Lines 592-609 in `diffEditorViewZones.ts`

---

#### Step 1.4: Final Mapping Alignment (line 339)

```lua
emit_alignment(mapping.original.end_line, mapping.modified.end_line)
```

**Purpose**: Create an alignment at the end of the mapping using the **mapping boundaries** (not inner change boundaries).

**Why this is critical**: This acts as a "safety net" that ensures the entire mapping is properly aligned, even if all inner change alignments were skipped.

**Example - Line 35**:
- Inner changes: All call `emit(35, ...)` which get skipped by the OR check
- Final alignment: `emit(36, 39)` using mapping end boundaries
- Result: Creates `[35,36)→[35,39)` with 3 fillers

**This is the "ground truth"**: The mapping boundaries from the C diff algorithm define the total affected lines. Inner changes provide detail, but the mapping defines the scope.

**VSCode reference**: Lines 610-615 in `diffEditorViewZones.ts`

---

### Phase 2: Converting Alignments to Fillers

**Location**: `lua/vscode-diff/render.lua`, lines 342-367  
**VSCode reference**: The filler insertion logic is integrated into VSCode's view zone creation

#### Step 2.1: Iterate Through Alignments

```lua
for _, align in ipairs(alignments) do
  local line_diff = align.mod_len - align.orig_len
  
  if line_diff > 0 then
    -- Modified has more lines: insert fillers in original
  elseif line_diff < 0 then
    -- Original has more lines: insert fillers in modified
  end
end
```

**Purpose**: For each alignment, calculate how many filler lines are needed and on which side.

---

#### Step 2.2: Calculate Filler Count and Position

```lua
if line_diff > 0 then
  table.insert(fillers, {
    buffer = 'original',
    after_line = align.orig_end - 1,
    count = line_diff
  })
elseif line_diff < 0 then
  table.insert(fillers, {
    buffer = 'modified',
    after_line = align.mod_end - 1,
    count = -line_diff
  })
end
```

**Position calculation**: `after_line = end - 1`

**Why subtract 1**:
- Ranges use exclusive end: `[35,36)` means line 35
- To insert fillers **after** line 35, we specify `after_line = 36 - 1 = 35`
- In Neovim's extmark API, `after_line = 35` means "below line 35"

**Example**:
```
Alignment: orig[35,36) → mod[35,39)
- orig_len = 1, mod_len = 4
- line_diff = 4 - 1 = 3
- Insert 3 fillers on original side
- Position: after_line = 36 - 1 = 35 (below line 35)
```

**VSCode reference**: VSCode creates view zones with similar positioning logic in `diffEditorViewZones.ts`

---

## Three Alignment Scenarios

The algorithm handles three distinct scenarios based on inner change characteristics:

### Scenario 1: BEFORE Alignment

**Triggers when**: Change starts mid-line (`start_col > 1`)

**Purpose**: Align unchanged text before the change

**Example from PS1 diff**:
```
Mapping [0]: Lines 14-14 → Lines 14-14
Inner: L14:C53-C53 → L14:C53-C54

Original: "    VERTEX MODE (Full Enterprise Setup with -Vertex)"
                                                          ^col 53
Modified: "    VERTEX MODE (Full Enterprise Setup with -Vertex):"
                                                          ^col 53
```

**Processing**:
1. BEFORE check: `53 > 1 and 53 > 1` → TRUE
2. Call `emit(14, 14)` with `first=true`
3. Sets `first=false`, creates empty alignment (skipped)
4. AFTER check: `53 <= 52` → FALSE (change at line end)
5. FINAL: `emit(15, 15)` creates `[14,15)→[14,15)` (no fillers)

**Result**: No fillers needed (same line count)

---

### Scenario 2: AFTER Alignment

**Triggers when**: Change ends before line end (`end_col ≤ line_len`)

**Purpose**: Align unchanged text after the change

**Example from PS1 diff**:
```
Mapping [4]: Lines 1216-1249 → Lines 1219-1269
Inner: L1216:C1-C1 → L1219:C1-L1222:C5

Original: "#region Step 5: Initialize Development Environment"
          ^col 1

Modified: (4 lines inserted before existing content)
```

**Processing**:
1. BEFORE check: `1 > 1` → FALSE (skip)
2. AFTER check: `1 <= 52` → TRUE
3. Call `emit(1216, 1222)` with `first=true`
4. Sets `first=false`, creates `[1216,1216)→[1219,1222)`
5. `orig_len=0, mod_len=3` → 3 fillers after line 1215

**Result**: 3 fillers inserted **before** line 1216 ✓

**Why this works**: The `first` flag allows the initial `emit(1216, 1222)` to proceed even though the original side hasn't advanced from position 1216.

---

### Scenario 3: FINAL Mapping Alignment Only

**Triggers when**: All inner change alignments are skipped

**Purpose**: Use mapping boundaries as "ground truth"

**Example from PS1 diff**:
```
Mapping [3]: Lines 35-35 → Lines 35-38
Inner: L35:C15-C15 → L35:C15-C20
Inner: L35:C20-C21 → L35:C25-L36:C9
Inner: L35:C26-C27 → L36:C14-L36:C15
Inner: L35:C50-C52 → L36:C38-L38:C5
```

**Processing**:

| Inner Change | BEFORE Check | AFTER Check | Result |
|--------------|--------------|-------------|--------|
| IC1 | `emit(35,35)` first=true | `emit(35,35)` | first→false, skipped |
| IC2 | `emit(35,35)` 35==35 | `emit(35,36)` 35==35 | SKIPPED |
| IC3 | `emit(35,36)` 35==35 | `emit(35,36)` 35==35 | SKIPPED |
| IC4 | `emit(35,36)` 35==35 | `emit(35,38)` 35==35 | SKIPPED |
| **FINAL** | — | — | `emit(36,39)` **CREATES** |

**Final alignment**:
- Calls `emit(36, 39)` using mapping end boundaries
- Check: `36 == 35 or 39 == 35` → FALSE (both advanced!)
- Creates `[35,36)→[35,39)` with `orig_len=1, mod_len=4`
- Inserts 3 fillers after line 35

**Result**: 3 fillers inserted **after** line 35 ✓

**Why this is critical**: When multiple inner changes occur on the same original line, the OR check prevents creating multiple redundant alignments. The FINAL alignment uses the mapping boundaries (which define the complete scope) to create the correct single alignment.

**Key insight**: The mapping says "modified has 4 total lines (35-38)" regardless of inner change details. The final alignment captures this truth.

---

## Why the OR Redundancy Check is Critical

The redundancy check distinguishes our correct implementation from a broken one:

### ❌ Wrong Implementation (AND Logic)

```lua
if orig_line_exclusive <= last_orig_line and mod_line_exclusive <= last_mod_line then
  return
end
```

**Problem**: Only skips when **both** sides haven't advanced.

**Line 35 result**:
- `emit(35, 36)`: Check `35 <= 35 AND 36 <= 35` → FALSE, proceeds
- `emit(35, 38)`: Check `35 <= 35 AND 38 <= 35` → FALSE, proceeds
- Creates multiple alignments: `[35,35)→[35,36)`, `[35,35)→[36,38)`, `[35,36)→[38,39)`
- Fillers placed at line 34 instead of line 35 ❌

### ✓ Correct Implementation (OR Logic + First Flag)

```lua
if first then
  first = false
elseif orig_line_exclusive == last_orig_line or mod_line_exclusive == last_mod_line then
  return
end
```

**Solution**: Skips when **either** side hasn't advanced (after first).

**Line 35 result**:
- First `emit(35, 35)`: `first=true` → proceeds, sets `first=false`
- `emit(35, 36)`: Check `35 == 35 OR 36 == 35` → TRUE, skip
- `emit(35, 38)`: Check `35 == 35 OR 38 == 35` → TRUE, skip
- Final `emit(36, 39)`: Check `36 == 35 OR 39 == 35` → FALSE, proceeds
- Creates single alignment: `[35,36)→[35,39)`
- Fillers placed after line 35 ✓

**The `first` flag prevents over-skipping**:
- Without it, `emit(1216, 1222)` would be skipped (1216 == 1216)
- With it, the initial alignment at the mapping start proceeds correctly

---

## Real-World Examples

### Example 1: Simple Text Insertion (Line 14)

**Change**: Added colon at end of line

**Data**:
```
Mapping [0]: orig[14,15), mod[14,15)
Inner: L14:C53-C53 → L14:C53-C54
```

**Flow**:
1. Initialize: `last_orig=14, last_mod=14, first=true`
2. BEFORE: `emit(14, 14)` → `first=false`, empty alignment
3. AFTER: Skipped (change at line end)
4. FINAL: `emit(15, 15)` → `[14,15)→[14,15)`, no fillers

**Result**: Both sides have 1 line, no fillers needed

---

### Example 2: Block Insertion (Line 1216)

**Change**: Inserted 3 lines before existing line

**Data**:
```
Mapping [4]: orig[1216,1250), mod[1219,1270)
Inner: L1216:C1-C1 → L1219:C1-L1222:C5
```

**Flow**:
1. Initialize: `last_orig=1216, last_mod=1219, first=true` (from previous mapping via global state)
2. Gap alignment: `handle_gap_alignment(1216, 1219)` creates alignment for gap
3. BEFORE: Skipped (starts at column 1)
4. AFTER: `emit(1216, 1222)` → `first=false`
   - Creates `[1216,1216)→[1219,1222)`: 0 lines → 3 lines
   - 3 fillers after line 1215 (before line 1216)
5. Subsequent inner changes create more alignments
6. FINAL: `emit(1250, 1270)` → Final alignment

**Result**: 3 fillers before line 1216, aligning the inserted block

---

### Example 3: Complex Multi-Line Change (Line 35)

**Change**: Modified 1 line that became 4 lines

**Data**:
```
Mapping [3]: orig[35,36), mod[35,39)
4 inner changes, all starting on original line 35
```

**Flow**:
1. Initialize: `last_orig=35, last_mod=35, first=true`
2. IC1: `emit(35, 35)` → `first=false`, no alignment created
3. IC2-4: All `emit(35, ...)` → skipped (35 == 35)
4. FINAL: `emit(36, 39)` → Creates `[35,36)→[35,39)`
   - 1 line → 4 lines = 3 fillers after line 35

**Result**: Single alignment with 3 fillers after line 35

**Why correct**: The mapping boundaries (36, 39) define the true scope, not the inner change details.

---

## References

### VSCode Implementation

**Primary file**: `src/vs/editor/browser/widget/diffEditor/features/diffEditorViewZones.ts`

Key functions:
- `computeRangeAlignment()` (lines 475-615): Main alignment logic
- `DiffMapping` type (lines 50-70): Data structure
- View zone creation (lines 350-450): Filler insertion

**Repository**: https://github.com/microsoft/vscode

### Our Implementation

**File**: `lua/vscode-diff/render.lua`

Key functions:
- `calculate_fillers()` (lines 283-367): Complete algorithm
- `emit_alignment()` (lines 290-318): Alignment creation
- Inner change processing (lines 322-336): BEFORE/AFTER checks
- Filler conversion (lines 342-367): Alignment to fillers

---

## Summary

The filler line algorithm ensures perfect visual alignment in side-by-side diff view through a carefully designed two-phase process:

**Phase 1 - Create Alignments**:
- Process inner changes with BEFORE and AFTER checks
- Use OR logic with first flag to prevent redundant alignments
- Apply final mapping alignment as safety net

**Phase 2 - Convert to Fillers**:
- Calculate line count differences
- Insert fillers on the shorter side
- Position fillers correctly using exclusive end notation

**Key design decisions**:
- **Global gap handling**: Maintains `last_orig_line`/`last_mod_line` across all mappings to process gaps between changes
- **OR redundancy check**: Prevents multiple alignments when original line hasn't advanced
- **First flag**: Allows initial alignment at mapping start
- **Final mapping alignment**: Ensures correctness using ground truth from diff algorithm

This implementation precisely matches VSCode's behavior, ensuring consistent diff rendering across both platforms.
