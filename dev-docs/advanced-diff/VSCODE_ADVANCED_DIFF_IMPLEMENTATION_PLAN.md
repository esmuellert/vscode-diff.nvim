# VSCode Diff Algorithm - Implementation Plan

## Overview

This document provides a comprehensive, step-by-step plan to implement VSCode's advanced diff algorithm for achieving pixel-perfect parity. The implementation follows a pipeline architecture where each step transforms data through well-defined types.

---

## Project Structure

### Recommended C Project Layout (Flat Structure)

C projects typically use **flat source structure** for simplicity and build efficiency. This is a best practice in C development.

```
c-diff-core/
├── include/
│   └── types.h                    # All public type definitions
├── src/
│   ├── myers.c                    # Step 1: Myers diff algorithm
│   ├── optimize.c                 # Steps 2-3: Diff optimization
│   ├── refine.c                   # Step 4: Character-level refinement
│   ├── mapping.c                  # Step 5: Line range mapping construction
│   ├── moved_lines.c              # Step 6: Move detection (optional)
│   ├── render_plan.c              # Step 7: Convert to render plan (STUB FIRST)
│   ├── utils.c                    # Utility functions (string, memory, etc.)
│   └── diff_core.c                # Main orchestrator + Lua FFI entry point
├── tests/
│   ├── test_myers.c
│   ├── test_optimize.c
│   ├── test_refine.c
│   ├── test_mapping.c
│   ├── test_moved_lines.c
│   ├── test_render_plan.c
│   └── test_integration.c
├── diff_core.h                    # Public API for Lua FFI
└── Makefile                       # Build system
```

**Why Flat Structure?**
- Standard C practice: Most C projects (Linux kernel, SQLite, Git) use flat or minimal hierarchy
- Easier to navigate: All source in one place
- Simpler builds: No complex include paths
- Better for small-to-medium projects (<50 files)

**Note:** We'll use this structure for the rewrite. The current `diff_core.c` will be replaced with a clean stub implementation.

---

## Required Utility Functions

These utilities are needed across multiple steps. VSCode implements them in various locations:

| Utility Function | Purpose | VSCode Reference |
|-----------------|---------|------------------|
| `string_hash()` | Hash strings for move detection | `src/vs/base/common/hash.ts` - `hash()` |
| `array_append()` | Dynamic array growth | `src/vs/base/common/arrays.ts` - `pushMany()` |
| `line_trim()` | Trim whitespace for comparison | `src/vs/base/common/strings.ts` - `trim()` |
| `char_at_utf8()` | Safe UTF-8 character access | `src/vs/base/common/strings.ts` - `getNextCodePoint()` |
| `range_contains()` | Check if range contains position | `src/vs/editor/common/core/range.ts` - `containsPosition()` |
| `range_intersect()` | Check range intersection | `src/vs/editor/common/core/range.ts` - `intersectRanges()` |
| `line_range_contains()` | Check if line range contains line | `src/vs/editor/common/core/ranges/lineRange.ts` - `contains()` |
| `line_range_delta()` | Shift line range by offset | `src/vs/editor/common/core/ranges/lineRange.ts` - `delta()` |
| `mem_grow()` | Realloc with error checking | Common pattern in C (not in VSCode) |
| `str_dup_safe()` | Safe string duplication | Common pattern in C (not in VSCode) |

**Implementation Note:** Create `src/utils.c` to house these helpers. This keeps algorithm code clean and focused.

---

## Type Validation Against VSCode

### Core Types (Verified ✓)

Our `types.h` accurately maps to VSCode's TypeScript types:

| Our C Type | VSCode TS Type | Location | Match |
|------------|----------------|----------|-------|
| `CharRange` | `Range` | `src/vs/editor/common/core/range.ts` | ✓ Perfect |
| `LineRange` | `LineRange` | `src/vs/editor/common/core/ranges/lineRange.ts` | ✓ Perfect |
| `RangeMapping` | `RangeMapping` | `src/vs/editor/common/diff/rangeMapping.ts` | ✓ Perfect |
| `DetailedLineRangeMapping` | `DetailedLineRangeMapping` | `src/vs/editor/common/diff/rangeMapping.ts` | ✓ Perfect |
| `SequenceDiff` | Internal to Myers | `src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/myersDiffAlgorithm.ts` | ✓ Compatible |

**Key Observations:**
- VSCode uses **1-based line numbers** (same as us ✓)
- VSCode uses **1-based column numbers** (same as us ✓)
- `LineRange.endLineNumber` is **exclusive** (same as us ✓)
- `Range.endColumn` is **exclusive** (same as us ✓)

---

## Implementation Pipeline

Each step transforms input to output through the algorithm pipeline:

```
Input: lines_a[], lines_b[]
  ↓
[Step 1: Myers Algorithm] → SequenceDiffArray (line-level)
  ↓
[Step 2: Optimize Diffs] → SequenceDiffArray (optimized)
  ↓
[Step 3: Remove Short Matches] → SequenceDiffArray (cleaned)
  ↓
[Step 4: Refine to Chars] → RangeMappingArray (char-level)
  ↓
[Step 5: Build Line Mappings] → DetailedLineRangeMappingArray
  ↓
[Step 6: Detect Moves] → LinesDiff (with moves)
  ↓
[Final: Create Render Plan] → RenderPlan
```

---

## Step 1: Myers Diff Algorithm

### Input/Output
- **Input:** `const char** lines_a/b`, `int count_a/b` (original file content)
- **Output:** `SequenceDiffArray*` (line-level differences)

### What It Does
Computes the shortest edit sequence using Myers' O(ND) algorithm. Produces a minimal set of line-level differences representing insertions, deletions, and modifications.

### VSCode Implementation Reference
- **Source:** `src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/myersDiffAlgorithm.ts`
- **Key Functions:**
  - `MyersDiffAlgorithm.compute()`
  - `computeDiff()` - Core Myers implementation

### Unit Tests to Implement
- **VSCode Test Location:** `src/vs/editor/test/common/diff/diffComputer.test.ts`
- **Test Cases:**
  1. Empty vs empty → no diffs
  2. Identical files → no diffs
  3. Single line insertion → 1 diff
  4. Single line deletion → 1 diff
  5. Multiple line changes → correct diff regions
  6. Large file performance test

---

## Step 2: Optimize Sequence Diffs

### Input/Output
- **Input:** `SequenceDiffArray*` (from Step 1), `const char** lines_a/b` (for context analysis)
- **Output:** `SequenceDiffArray*` (optimized - modified in-place)

### What It Does
Shifts diff boundaries to more intuitive positions (e.g., moving changes to blank lines or natural code boundaries). Joins adjacent diffs when beneficial for readability.

### VSCode Implementation Reference
- **Source:** `src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/diffAlgorithm.ts`
- **Key Functions:**
  - `optimizeSequenceDiffs()`
  - `shiftSequenceDiffs()` - Shift to better boundaries
  - `removeShortMatches()` - Preview of step 3

### Unit Tests to Implement
- **VSCode Test Location:** `src/vs/editor/test/common/diff/diffComputer.test.ts`
- **Test Cases:**
  1. Shift diff to blank line
  2. Shift diff to brace boundary
  3. Join adjacent diffs with 1-line gap
  4. Preserve meaningful separation

---

## Step 3: Remove Very Short Matches

### Input/Output
- **Input:** `SequenceDiffArray*` (from Step 2), `const char** lines_a/b` (for context), `int max_match_len`
- **Output:** `SequenceDiffArray*` (cleaned - modified in-place)

### What It Does
Merges diff regions separated by very short unchanged sequences (typically 1-2 lines). Improves visual coherence by treating closely related changes as single units.

### VSCode Implementation Reference
- **Source:** `src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/diffAlgorithm.ts`
- **Key Functions:**
  - `removeVeryShortMatchingLinesBetweenDiffs()`
  - `removeVeryShortMatchingTextBetweenDiffs()` - Character-level version

### Unit Tests to Implement
- **VSCode Test Location:** `src/vs/editor/test/common/diff/diffComputer.test.ts`
- **Test Cases:**
  1. Merge diffs with 1-line gap
  2. Keep diffs with 3+ line gap
  3. Edge case: start/end of file
  4. Multiple consecutive short matches

---

## Step 4: Refine to Character Level

### Input/Output
- **Input:** `SequenceDiffArray*` (from Step 3 - line-level), `const char** lines_a/b` (for text content)
- **Output:** `RangeMappingArray*` (character-level differences within changed lines)

### What It Does
For each line-level diff region, computes character-by-character differences using Myers algorithm again. This enables precise highlighting of changed text within lines.

### VSCode Implementation Reference
- **Source:** `src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts`
- **Key Functions:**
  - `computeMovedLines()` (contains refinement logic)
  - `MyersDiffAlgorithm.compute()` - Reused for character-level
  - Character sequence handling in `DiffAlgorithmResult`

### Unit Tests to Implement
- **VSCode Test Location:** `src/vs/editor/test/common/diff/diffComputer.test.ts`
- **Test Cases:**
  1. Single word change in line
  2. Multiple changes in one line
  3. Whitespace-only changes
  4. Empty line vs content line
  5. Full line replacement

---

## Step 5: Build Line Range Mappings

### Input/Output
- **Input:** `RangeMappingArray*` (from Step 4 - char-level), `SequenceDiffArray*` (from Step 3 - line-level context)
- **Output:** `DetailedLineRangeMappingArray*` (line ranges with embedded char changes)

### What It Does
Groups character-level changes by line range. Creates `DetailedLineRangeMapping` objects that combine line-level regions with their inner character changes.

### VSCode Implementation Reference
- **Source:** `src/vs/editor/common/diff/rangeMapping.ts`
- **Key Functions:**
  - `lineRangeMappingFromRangeMappings()`
  - `getLineRangeMapping()` - Single mapping conversion
  - `DetailedLineRangeMapping.fromRangeMappings()`

### Unit Tests to Implement
- **VSCode Test Location:** `src/vs/editor/test/common/diff/diffComputer.test.ts`
- **Test Cases:**
  1. Single-line change → 1 DetailedLineRangeMapping
  2. Multi-line change → 1 DetailedLineRangeMapping with multiple inner changes
  3. Adjacent line changes → Separate mappings
  4. Touching line changes → Single merged mapping

---

## Step 6: Detect Moved Code (Optional)

### Input/Output
- **Input:** `DetailedLineRangeMappingArray*` (from Step 5), `const char** lines_a/b` (for content hashing)
- **Output:** `MovedTextArray*` (detected move operations)

### What It Does
Identifies code blocks that were moved (cut from one location, pasted in another). Helps distinguish moves from delete+insert pairs. This output is stored in `LinesDiff` alongside the changes but is **optional** for rendering.

### VSCode Implementation Reference
- **Source:** `src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts`
- **Key Functions:**
  - `computeMovedLines()`
  - `computeMovedLineMappings()`
  - Hashing and matching logic for identical blocks

### Unit Tests to Implement
- **VSCode Test Location:** `src/vs/editor/test/common/diff/diffComputer.test.ts`
- **Test Cases:**
  1. Function moved to different location
  2. Multiple blocks moved
  3. Block moved and modified (should not detect)
  4. Partial move (only some lines)

---

## Final Step: Create Render Plan

### Input/Output
- **Input:** 
  - `LinesDiff*` (contains `DetailedLineRangeMappingArray` from Step 5, optionally `MovedTextArray` from Step 6)
  - `const char** lines_a/b`, `int count_a/b` (original text - needed to extract actual content for highlights)
- **Output:** `RenderPlan*` (UI-ready with text content + highlight positions)

### What It Does
Transforms coordinate-based algorithm output into rendering instructions with actual text content. Extracts character substrings using the coordinates from `DetailedLineRangeMappingArray` and creates line highlights, character highlights, and filler lines for alignment. Prepares separate left/right buffer metadata.

### VSCode Implementation Reference
- **Source:** `src/vs/browser/widget/diffEditor/*`
- **Key Concepts:**
  - Decoration types (line/char highlights)
  - Virtual/filler line insertion
  - Side-by-side alignment

### Unit Tests to Implement
- **Test Cases:**
  1. Simple diff → correct highlights
  2. Multi-line change → proper alignment
  3. Move detection → move decorations
  4. Empty diff → no highlights

---

## Testing Strategy

### Unit Tests (Per Step)
Each module has isolated tests verifying correctness:
- Input/output validation
- Edge cases (empty, single-line, large files)
- VSCode parity verification using their test cases

### Integration Tests
- **Full Pipeline:** Feed real file diffs through entire pipeline
- **VSCode Comparison:** Compare our output against VSCode's expected results
- **Performance:** Benchmark against large files (1000+ lines)

### Test Data Sources
1. **VSCode Test Suite:** Use test cases from `src/vs/editor/test/common/diff/diffComputer.test.ts`
2. **Real-World Files:** Common programming scenarios (refactoring, bug fixes)
3. **Edge Cases:** Empty files, binary-like content, very long lines

---

## Implementation Order

1. ✅ **types.h** - Define all types (DONE)
2. **myers.c** - Implement Myers algorithm + tests
3. **optimize.c** - Implement optimization passes + tests
4. **refine.c** - Character-level refinement + tests
5. **mapping.c** - Line range mapping construction + tests
6. **moved_lines.c** - Move detection + tests
7. **render_plan.c** - Render plan generation + tests
8. **diff_core.c** - Main orchestrator
9. **Integration tests** - End-to-end verification

---

## Success Criteria

- [ ] All unit tests pass
- [ ] Integration tests match VSCode output on 20+ test cases
- [ ] Performance acceptable (<100ms for 500-line files)
- [ ] Pixel-perfect UI parity with VSCode diff view
- [ ] No memory leaks (valgrind clean)

---

## References

### VSCode Source Files
1. **Myers Algorithm:** `src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/myersDiffAlgorithm.ts`
2. **Optimization:** `src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/diffAlgorithm.ts`
3. **Types:** `src/vs/editor/common/diff/rangeMapping.ts`
4. **Main Computer:** `src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts`
5. **Tests:** `src/vs/editor/test/common/diff/diffComputer.test.ts`

### Key Insights
- VSCode's algorithm is highly optimized for **human-readable diffs**
- **Shifting boundaries** to natural breakpoints is critical for UX
- **Character-level refinement** enables precise inline highlighting
- **Move detection** improves understanding of refactoring changes
