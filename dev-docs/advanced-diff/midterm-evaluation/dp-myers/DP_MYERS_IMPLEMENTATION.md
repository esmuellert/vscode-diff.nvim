# DP Myers Algorithm Implementation - Development Log

**Date:** 2025-10-25  
**Status:** ⚠️ PARTIAL
**VSCode Parity:** ~80% – Core DP engine implemented, but auto-selection still lacks VSCode's equality scoring hook

## Overview

Implemented the missing Dynamic Programming (DP) variant of the Myers diff algorithm to get much closer to VSCode's diff computation. Previously, our implementation only used the O(ND) Myers algorithm for all inputs, but VSCode uses a size-based selection strategy:

- **Small sequences**: O(MN) DP algorithm with LCS-based scoring
- **Large sequences**: O(ND) Myers forward algorithm

## Implementation Details

### Files Modified

1. **`include/myers.h`**
   - Added `EqualityScoreFn` typedef for optional scoring in DP algorithm
   - Added `myers_dp_diff_algorithm()` - new DP implementation
   - Added `myers_nd_diff_algorithm()` - renamed original O(ND) implementation
   - Modified `myers_diff_algorithm()` - now dispatches based on size

2. **`src/myers.c`**
   - Implemented `myers_dp_diff_algorithm()` - Full O(MN) DP algorithm
     - Uses 3 matrices: lcsLengths, directions, lengths
     - Supports optional equality scoring function
     - Prefers consecutive diagonals for better diff quality
     - Backtracks to build SequenceDiff array
   - Implemented automatic algorithm selection in `myers_diff_algorithm()`
     - Lines: DP if total < 1700, otherwise O(ND)
     - ⚠️ TODO: Pass VSCode's equality scoring function when dispatching to DP
     - Provides flexibility for char-level code to use different threshold
   - Renamed original implementation to `myers_nd_diff_algorithm()`

3. **`src/char_level.c`**
   - Modified `refine_diff()` to use 500-char threshold
   - Explicitly calls `myers_dp_diff_algorithm()` for small char sequences (< 500)
   - Explicitly calls `myers_nd_diff_algorithm()` for large char sequences (>= 500)

## Remaining Parity Work

- **Line-level scoring hook:** VSCode forwards a weighting callback when it selects the DP path so that trimmed-equal lines with different whitespace still prefer alignment. The C dispatcher currently calls `myers_dp_diff_algorithm(..., NULL, NULL)`, so whitespace-only edits on short files will not match VSCode's behavior yet.
- **Line hash inputs:** VSCode hashes `l.trim()` before diffing; confirm whether our `LineSequence` instances for mainline diffing should also opt into trimmed hashing when parity work resumes.

### Reference: VSCode DP Scoring Callback

```ts
return this.dynamicProgrammingDiffing.compute(
        sequence1,
        sequence2,
        timeout,
        (offset1, offset2) =>
                originalLines[offset1] === modifiedLines[offset2]
                        ? modifiedLines[offset2].length === 0
                                ? 0.1
                                : 1 + Math.log(1 + modifiedLines[offset2].length)
                        : 0.99
);
```

### Algorithm Selection Strategy

**Line-level (myers_diff_algorithm):**
```c
if (total < 1700) {
    return myers_dp_diff_algorithm(...);
} else {
    return myers_nd_diff_algorithm(...);
}
```

**Char-level (refine_diff):**
```c
if (len1 + len2 < 500) {
    diffs = myers_dp_diff_algorithm(...);
} else {
    diffs = myers_nd_diff_algorithm(...);
}
```

### VSCode References

- **DP Algorithm**: `dynamicProgrammingDiffing.ts`
- **O(ND) Algorithm**: `myersDiffAlgorithm.ts`
- **Selection Logic**: `defaultLinesDiffComputer.ts` (lines 66-87, 224-226)

## Testing

### New Test Suite: `test_dp_algorithm.c`

Created comprehensive test suite with 4 test cases:

1. **test_small_sequence_uses_dp()** - Verifies DP is used for small sequences (< 1700)
2. **test_char_sequence_threshold()** - Verifies 500-char threshold for char sequences
3. **test_dp_with_equality_scoring()** - Tests optional scoring function
4. **test_large_sequence_uses_myers()** - Verifies O(ND) is used for large sequences (> 1700)

All tests verify that both algorithms produce identical results, ensuring correctness.

### Test Results

```
=== Test: Small Sequence Uses DP ===
✓ All algorithms produce same result
✓ Auto-select uses DP for small sequence (total=8 < 1700)
✓ PASSED

=== Test: Character Sequence Threshold ===
✓ Both algorithms produce same result for char sequences
✓ Total chars (22) < 500, DP is appropriate
✓ PASSED

=== Test: DP with Equality Scoring ===
✓ DP algorithm with scoring function works
✓ PASSED

=== Test: Large Sequence Uses Myers O(ND) ===
✓ Auto-select uses O(ND) for large sequence
✓ PASSED
```

### Existing Tests

All existing tests continue to pass:
- ✅ test_myers - 11/11 tests pass
- ✅ test_line_optimization - 10/10 tests pass
- ✅ test_char_level - 10/10 tests pass
- ✅ test_dp_algorithm - 4/4 tests pass

## Technical Implementation Notes

### DP Algorithm Details

The DP implementation follows VSCode's approach exactly:

1. **Three Matrices:**
   - `lcsLengths[i][j]` - Length of LCS up to positions i, j
   - `directions[i][j]` - Direction taken (1=horizontal, 2=vertical, 3=diagonal)
   - `lengths[i][j]` - Length of consecutive diagonals (for quality optimization)

2. **Diagonal Preference:**
   - When consecutive diagonals are detected, adds bonus to score
   - Produces higher quality diffs with fewer fragmented changes

3. **Equality Scoring:**
   - Supports optional `EqualityScoreFn` for custom element scoring
   - VSCode uses this for line-level scoring (empty lines get 0.1, others get 1 + log(1 + length))
   - Currently uses default scoring (1.0) but infrastructure is in place

4. **Backtracking:**
   - Two-pass approach: first count diffs, then build result array
   - Emits diffs in forward order (matches VSCode output)

### Memory Considerations

**DP Algorithm (O(MN) space):**
- Suitable for small sequences
- 3 matrices of size M×N
- For 1700 lines: ~17MB (3 × 1700 × 1700 × 8 bytes)

**O(ND) Algorithm (O(N) space):**
- Suitable for large sequences
- Dynamic arrays that grow as needed
- Much more memory efficient for large files

The threshold of 1700 provides a good balance between accuracy (DP) and efficiency (O(ND)).

## External API Impact

**✅ NO BREAKING CHANGES**

The external API remains unchanged:
- `myers_diff_algorithm()` is still the main entry point
- Function signature is identical
- Automatic selection happens internally
- Callers don't need any code changes

Advanced users can call `myers_dp_diff_algorithm()` or `myers_nd_diff_algorithm()` directly if they want explicit control.

## Parity Assessment

### Before This Implementation
- **Step 1 Parity:** 0.6/1.0 (partial) - Missing DP algorithm for small files
- **Note:** Previous docs incorrectly claimed "full parity"

### After This Implementation
- **Step 1 Parity:** ~0.8/1.0 (still partial) - DP core matches VSCode, but dispatcher lacks the equality-scoring callback so whitespace-only tweaks on short files diverge.
- **Algorithm Selection:** ✅ Matches VSCode thresholds and branching logic
- **Thresholds:** ✅ 1700 for lines, 500 for chars (VSCode values)
- **Implementation:** ✅ DP/ND internals mirror VSCode structure and data flow
- **Behavior:** ⚠️ Small, whitespace-sensitive diffs will differ until the scoring hook is wired up

## What Was Missing (Historical Context)

The midterm evaluation document stated "partial parity" for Step 1 with this note:

> "However, VS Code swaps to the dynamic-programming scorer for small inputs, while the C port always stays on Myers, so the parity is only partial."

This was correct but the implication wasn't clear in other documentation. We were always using Myers O(ND), missing:

1. The DP algorithm implementation itself
2. The size-based selection logic
3. The different thresholds for lines vs chars

The structural gap (missing DP engine and thresholds) is now closed, but parity work must finish by feeding VSCode's scoring callback and reviewing the line-hash inputs described above.

## Next Steps

- **Wire equality scoring:** Export a helper that computes the same weights VSCode passes to `DynamicProgrammingDiffing.compute` and supply it from the line-level caller when the DP branch is chosen.
- **Audit hashing mode:** Decide whether `line_sequence_create(..., true)` should be used so hashes match VSCode's `trim()` preprocessing when parity is enforced end-to-end.
- **Expand tests:** Add regression coverage that exercises whitespace-only deltas below the DP threshold to capture the current mismatch and guard the eventual fix.

## Conclusion

⚠️ **Parity Still Pending Final Wiring**

We now have:
- Full DP algorithm implementation matching VSCode's `dynamicProgrammingDiffing.ts`
- Automatic algorithm selection matching VSCode's thresholds exactly
- Comprehensive test coverage verifying correctness of the DP core
- No breaking changes to external API
- All existing tests continue to pass

Remaining work is focused on feeding the equality-scoring callback (and potentially aligning hashing) so that short, whitespace-sensitive diffs behave identically to VSCode. Until that is delivered, the parity score remains partial.
