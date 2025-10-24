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
│   ├── optimize.c                 # Steps 2-3: Diff optimization (generic, used by both line & char)
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
[Step 2: Optimize Diffs] → SequenceDiffArray (shifted & joined via boundary analysis)
  ↓
[Step 3: Remove Short Matches] → SequenceDiffArray (merged if gap ≤ 2 lines)
  ↓
[Step 4: Refine to Chars] → For EACH line diff:
  │  ├─> Myers on chars → SequenceDiff[] (char offsets)
  │  ├─> Optimize chars (REUSES Step 2 algorithm)
  │  ├─> Extend to word boundaries
  │  ├─> Remove short matches (REUSES Step 3 concept)
  │  └─> Translate to (line,col) → RangeMapping[]
  ↓
[Step 5: Build Line Mappings] → DetailedLineRangeMappingArray
  ↓
[Step 6: Detect Moves] → LinesDiff (with moves)
  ↓
[Final: Create Render Plan] → RenderPlan
```

**Key Insight:** Steps 2-3 optimization algorithms are GENERIC and reused for both line-level (Steps 2-3) and character-level (within Step 4) sequences.

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
- **Note:** VSCode has minimal tests for advanced diff (only 5 tests total in `defaultLinesDiffComputer.test.ts`, with just 1 basic Myers test). The following are our comprehensive test cases:
- **Test Cases:**
  1. Empty vs empty → no diffs
  2. Identical files → no diffs
  3. Single line insertion → 1 diff
  4. Single line deletion → 1 diff
  5. Single line modification → 1 diff (explicit modify test)
  6. Multiple separate diffs → correct diff array
  7. Interleaved changes → insert, delete, modify mixed
  8. Completely different files → 1 large diff
  9. Snake following verification → diagonal matching works
  10. Large file performance test (500+ lines)
  11. Worst-case scenario → maximum edit distance

---

## Step 2: Optimize Sequence Diffs

### Input/Output
- **Input:** `SequenceDiffArray*` (from Step 1), `const char** lines_a/b` (for context analysis)
- **Output:** `SequenceDiffArray*` (optimized - modified in-place)

### What It Does
Applies sophisticated optimization to diffs. First, shifts insertions/deletions left then right to find mergeable diffs (via `joinSequenceDiffsByShifting` - called twice). Then, shifts diff boundaries to preferred positions using boundary scores (`shiftSequenceDiffs`). **Note:** This is a generic algorithm reused for both line-level and character-level sequences in VSCode.

### VSCode Implementation Reference
- **Source:** `src/vs/editor/common/diff/defaultLinesDiffComputer/heuristicSequenceOptimizations.ts`
- **Key Functions:**
  - `optimizeSequenceDiffs()` - Main entry point, calls sub-functions
  - `joinSequenceDiffsByShifting()` - Shifts empty ranges left/right to merge with neighbors
  - `shiftSequenceDiffs()` - Uses `getBoundaryScore()` for smart boundary placement

### Unit Tests to Implement
- **Note:** VSCode doesn't have isolated tests for this step. The following are our test cases:
- **Test Cases:**
  1. Shift diff to blank line
  2. Shift diff to brace boundary
  3. Join two diffs via shifting empty ranges
  4. Keep two diffs with incompatible positions
  5. Optimize at file start (boundary case)
  6. Optimize at file end (boundary case)
  7. No optimization needed (already optimal)
  8. Multiple diffs, some joinable via shifting

---

## Step 3: Remove Very Short Matches

### Input/Output
- **Input:** `SequenceDiffArray*` (from Step 2), `const char** lines_a/b` (for context), `int max_match_len`
- **Output:** `SequenceDiffArray*` (cleaned - modified in-place)

### What It Does
For line-level: Joins diffs separated by very short unchanged regions (gap ≤ 2 lines in either sequence) using `removeVeryShortMatchingLinesBetweenDiffs()`. Iterates up to 10 times until no more joins occur. For character-level: Uses different variants (`removeShortMatches()` and `removeVeryShortMatchingTextBetweenLongDiffs()`). Improves visual coherence by treating closely related changes as single units.

### VSCode Implementation Reference
- **Source:** `src/vs/editor/common/diff/defaultLinesDiffComputer/heuristicSequenceOptimizations.ts`
- **Key Functions:**
  - `removeVeryShortMatchingLinesBetweenDiffs()` - Line-level variant, gap ≤ 2
  - `removeShortMatches()` - Character-level variant, different logic
  - `removeVeryShortMatchingTextBetweenLongDiffs()` - Character-level for long diffs

### Unit Tests to Implement
- **Note:** VSCode doesn't have isolated tests for this step. The following are our test cases:
- **Test Cases:**
  1. Merge diffs with 1-line gap
  2. Merge diffs with 2-line gap (threshold)
  3. Keep diffs with 3+ line gap
  4. Edge case: start/end of file
  5. Multiple consecutive short matches
  6. Iterative merging (requires multiple passes)
  7. Cascading merges (A+B, then (A+B)+C)
  8. Zero-line gap (adjacent diffs)

---

## Step 4: Refine to Character Level

### Input/Output
- **Input:** `SequenceDiffArray*` (from Step 3 - line-level), `const char** lines_a/b` (for text content)
- **Output:** `RangeMappingArray*` (character-level differences within changed lines)

### What It Does
For each line-level diff region: (1) Creates character sequences with line boundary tracking (via `LinesSliceCharSequence`), (2) Runs Myers on characters, (3) Applies SAME optimization pipeline as Steps 2-3 but on character sequences: `optimizeSequenceDiffs()`, `extendDiffsToEntireWordIfAppropriate()` for word boundaries, `removeShortMatches()`, and `removeVeryShortMatchingTextBetweenLongDiffs()`, (4) Translates character offsets to (line, column) positions using boundary tracking. Enables precise word-aligned inline highlighting.

### VSCode Implementation Reference
- **Source:** `src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts`
- **Key Functions:**
  - `refineDiff()` - Main character refinement function (lines 144-173)
  - `LinesSliceCharSequence` - Tracks line boundaries, implements `getBoundaryScore()`, `translateOffset()`
  - Post-processing: `optimizeSequenceDiffs()`, `extendDiffsToEntireWordIfAppropriate()`, `removeShortMatches()`, `removeVeryShortMatchingTextBetweenLongDiffs()`

### Unit Tests to Implement
- **Note:** VSCode doesn't have isolated tests for this step. The following are our test cases:
- **Test Cases:**
  1. Single word change in line (verify word boundary extension)
  2. Multiple changes in one line
  3. Multi-line diff (verify line boundary tracking)
  4. Whitespace-only changes (with/without considerWhitespaceChanges)
  5. Empty line vs content line
  6. Full line replacement
  7. UTF-8 multibyte characters (e.g., "café" → "cafe")
  8. Emoji changes (e.g., "hello👋" → "hello")
  9. Tab vs spaces (e.g., "\t" vs "    ")
  10. CamelCase subword extension (if extendToSubwords enabled)

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
- **Note:** VSCode doesn't have isolated tests for this step. The following are our test cases:
- **Test Cases:**
  1. Single-line change → 1 DetailedLineRangeMapping
  2. Multi-line change → 1 DetailedLineRangeMapping with multiple inner changes
  3. Adjacent line changes → Separate mappings
  4. Touching line changes → Single merged mapping
  5. Empty line in mapping
  6. Very large mapping (100+ lines)

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
- **Note:** VSCode doesn't have isolated tests for this step. The following are our test cases:
- **Test Cases:**
  1. Function moved to different location
  2. Multiple blocks moved
  3. Block moved and modified (should not detect)
  4. Partial move (only some lines)
  5. Hash collision handling
  6. Move within move (nested scenarios)
  7. Minimum block size threshold
  8. Identical duplicate blocks

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
- **Note:** VSCode doesn't have isolated tests for this step. The following are our test cases:
- **Test Cases:**
  1. Simple diff → correct highlights
  2. Multi-line change → proper alignment
  3. Move detection → move decorations
  4. Empty diff → no highlights
  5. Filler lines for alignment
  6. Very wide lines (wrapping behavior)
  7. Side-by-side alignment sync
  8. Mixed decoration types

---

## Testing Strategy

### Unit Tests (Per Step)
Each module has isolated tests verifying correctness:
- Input/output validation
- Edge cases (empty, single-line, large files)
- Error handling (null input, invalid data)
- Memory safety (no leaks, proper cleanup)
- Performance bounds (time constraints)

### Integration Tests
- **Full Pipeline:** Feed real file diffs through entire pipeline
- **VSCode Comparison:** Compare our output against VSCode's expected results
- **Performance:** Benchmark against large files (1000+ lines)
- **Cross-Step:** Verify data flow between pipeline stages

### Additional Test Suites
**Error Handling:**
- Null/invalid input handling
- Negative counts
- Invalid UTF-8 sequences

**Memory Safety:**
- Memory leak detection (valgrind)
- Large allocation stress tests
- Proper cleanup verification

**Performance:**
- Each step < 50ms for typical files
- Large file benchmarks (500, 5000 lines)
- Worst-case complexity bounds

### Test Data Sources
1. **VSCode Advanced Tests:** `defaultLinesDiffComputer.test.ts` (5 tests - limited coverage)
2. **Real-World Files:** Common programming scenarios (refactoring, bug fixes)
3. **Synthetic Edge Cases:** Crafted for boundary conditions
4. **Adversarial Cases:** Worst-case complexity scenarios

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
2. **Optimization (Steps 2-3):** `src/vs/editor/common/diff/defaultLinesDiffComputer/heuristicSequenceOptimizations.ts`
3. **Main Computer (Step 4):** `src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts`
4. **Character Sequences:** `src/vs/editor/common/diff/defaultLinesDiffComputer/linesSliceCharSequence.ts`
5. **Types:** `src/vs/editor/common/diff/rangeMapping.ts`
6. **Tests:** `src/vs/editor/test/common/diff/diffComputer.test.ts`

### Key Insights
- VSCode's algorithm is highly optimized for **human-readable diffs**
- **Shifting boundaries** to natural breakpoints is critical for UX
- **Character-level refinement** enables precise inline highlighting
- **Move detection** improves understanding of refactoring changes
