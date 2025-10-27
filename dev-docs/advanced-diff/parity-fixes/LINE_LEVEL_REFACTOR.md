# Line-Level Consolidation Refactor

## Overview
Created `line_level.c` module to consolidate Steps 1-3 of the line-level diff pipeline, matching VSCode's architecture in `defaultLinesDiffComputer.ts`.

## Changes Made

### New Files
1. **`c-diff-core/include/line_level.h`**
   - Public API for line-level diff computation
   - Main function: `compute_line_alignments()` - consolidates Steps 1-3
   - Exact equivalent of VSCode's `lineAlignments` variable (line 245)

2. **`c-diff-core/src/line_level.c`**
   - Implementation of consolidated line-level pipeline
   - Pipeline: Hash creation → Myers diff → optimize → removeVeryShort
   - Includes line equality scoring for DP algorithm
   - Full VSCode parity with `defaultLinesDiffComputer.ts` lines 224-245

### Modified Files
1. **`c-diff-core/Makefile`**
   - Added `LINE_LEVEL_SRC` variable
   - Updated all relevant test targets to include `line_level.c`
   - Tests now link: `line_level.c`, `myers.c`, `optimize.c`, `sequence.c`, etc.

## Architecture

### Before Refactor
```
Tests → myers.c + optimize.c (manual pipeline construction)
```

### After Refactor
```
Tests → line_level.c → myers.c + optimize.c (consolidated pipeline)
       ↓
       compute_line_alignments() // One-call API
```

### Module Responsibilities

**`optimize.c`** - Shared optimization primitives (used by both line and char level):
- `optimize_sequence_diffs()` - Step 2 (joinSequenceDiffsByShifting + shiftSequenceDiffs)
- `remove_short_matches()` - Remove ≤2 gaps (used in Step 3 and Step 4)
- `remove_very_short_matching_lines_between_diffs()` - LINE-SPECIFIC Step 3

**`line_level.c`** - Line-level pipeline consolidation (Steps 1-3):
- `compute_line_alignments()` - Full pipeline orchestration
- Perfect hash map creation
- Algorithm selection (DP for <1700 lines, O(ND) for larger)
- Equality scoring for DP
- Calls optimize_sequence_diffs() and remove_very_short_matching_lines_between_diffs()

**`char_level.c`** - Character-level pipeline (Step 4):
- Uses `optimize.c` primitives for character sequences
- Will eventually use `line_level.c` output as input

## VSCode Parity Mapping

| VSCode Code | Our Code |
|------------|----------|
| `defaultLinesDiffComputer.ts:68-75` | `line_level.c`: Hash map creation |
| `defaultLinesDiffComputer.ts:77-81` | `line_level.c`: LineSequence creation |
| `defaultLinesDiffComputer.ts:83-97` | `line_level.c`: Algorithm selection (DP vs O(ND)) |
| `defaultLinesDiffComputer.ts:244` | `line_level.c`: optimize_sequence_diffs() call |
| `defaultLinesDiffComputer.ts:245` | `line_level.c`: remove_very_short_matching_lines_between_diffs() call |
| **Variable: `lineAlignments`** | **Return value of `compute_line_alignments()`** |

## Testing

All existing tests pass without modification:
- ✓ `test-myers` - Myers algorithm tests
- ✓ `test-line-opt` - Line optimization pipeline tests (Steps 1+2+3)
- ✓ `test-line-boundary` - Boundary scoring demonstration
- ✓ `test-char-level` - Character-level tests (Step 4)
- ✓ `test-dp` - DP algorithm selection tests

Additional test created:
- `tests/test_line_level_api.c` - Verifies `compute_line_alignments()` API

## Benefits

1. **Better Architecture**: Mirrors VSCode's structure exactly
2. **Cleaner API**: One function call instead of manual pipeline construction
3. **Modularity**: `optimize.c` contains shared primitives, `line_level.c` orchestrates line-level usage
4. **No Side Effects**: Refactor is purely organizational - all tests pass unchanged
5. **Future Ready**: `char_level.c` can use `line_level.c` output for Step 4 orchestration

## No Breaking Changes

- Existing test code continues to work
- Individual step functions remain accessible
- Only added new consolidated API, didn't remove anything
- Pure code organization improvement

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    VSCode Diff Pipeline                      │
└─────────────────────────────────────────────────────────────┘

┌───────────────────┐
│   line_level.c    │  ← NEW: Consolidates Steps 1-3 for lines
│  (Orchestrator)   │
└─────────┬─────────┘
          │
          ├──→ myers.c          (Step 1: Diff algorithm)
          │    ├─ myers_diff_algorithm()
          │    ├─ myers_dp_diff_algorithm()
          │    └─ myers_nd_diff_algorithm()
          │
          └──→ optimize.c       (Steps 2-3: Shared optimizations)
               ├─ optimize_sequence_diffs()              [Step 2]
               ├─ remove_short_matches()                 [Step 3 helper]
               └─ remove_very_short_matching_lines_*()   [Step 3 line-specific]

┌───────────────────┐
│   char_level.c    │  ← Step 4: Character-level refinement
└─────────┬─────────┘
          │
          ├──→ line_level.c     (Gets line alignments)
          ├──→ myers.c          (Diff on characters)
          └──→ optimize.c       (Optimize character diffs)

┌────────────────────────────────────────────────────────────┐
│  Infrastructure (sequence.c, string_hash_map.c, utils.c)   │
└────────────────────────────────────────────────────────────┘
```

## Code Example

### Before (Manual Pipeline)
```c
// Create sequences
StringHashMap* hash_map = string_hash_map_create();
ISequence* seq1 = line_sequence_create(lines_a, len_a, false, hash_map);
ISequence* seq2 = line_sequence_create(lines_b, len_b, false, hash_map);

// Step 1: Myers diff
bool timeout = false;
SequenceDiffArray* diffs = myers_diff_algorithm(seq1, seq2, 5000, &timeout);

// Step 2: Optimize
diffs = optimize_sequence_diffs(seq1, seq2, diffs);

// Step 3: Remove very short
diffs = remove_very_short_matching_lines_between_diffs(seq1, seq2, diffs);

// Cleanup
seq1->destroy(seq1);
seq2->destroy(seq2);
string_hash_map_destroy(hash_map);
```

### After (Consolidated API)
```c
// One function call - all steps handled internally
bool timeout = false;
SequenceDiffArray* line_alignments = compute_line_alignments(
    lines_a, len_a,
    lines_b, len_b,
    5000,  // timeout_ms
    &timeout
);

// Use result
// ...

// Cleanup
free_sequence_diff_array(line_alignments);
```

## Summary

This refactor makes our codebase match VSCode's architecture more closely while maintaining full backward compatibility. The `line_level.c` module provides a clean, high-level API for line-level diff computation that exactly mirrors VSCode's `lineAlignments` computation in `defaultLinesDiffComputer.ts`.
