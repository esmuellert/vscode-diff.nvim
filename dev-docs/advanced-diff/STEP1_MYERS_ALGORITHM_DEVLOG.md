# Step 1: Myers O(ND) Algorithm Implementation - Development Log

## Date: 2025-10-23

### Goal
Implement VSCode-parity Myers O(ND) diff algorithm as the foundation for the advanced diff pipeline.

### Key Decision: Forward-Only Myers Algorithm

After studying VSCode's actual implementation, discovered they use a **forward-only** Myers algorithm, not the bidirectional middle-snake approach I initially attempted.

**VSCode's Implementation:**
- File: `src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/myersDiffAlgorithm.ts`
- Approach: Forward-only search, tracking paths through a V array of X coordinates
- Complexity: O(ND) time, O(N+M) space

### Implementation Strategy

Built the algorithm incrementally:

1. **Data Structures (Step 1a)**
   - `IntArray`: Dynamic array supporting negative indices for the V array
   - `PathArray`: Dynamic array for tracking SnakePath pointers
   - `SnakePath`: Linked list structure to reconstruct diff path

2. **Core Algorithm (Step 1b)**
   - Initialize with diagonal matching from (0,0)
   - Iterate through edit distances `d = 0, 1, 2, ...`
   - For each diagonal `k`, compute furthest reaching d-path
   - Track paths to enable result reconstruction

3. **Result Building (Step 1c)**
   - Walk backward through final path
   - Collect diff regions (non-diagonal segments)
   - Return as `SequenceDiffArray`

### Test Results

All tests passing:
- ✓ Empty files
- ✓ Identical files  
- ✓ One line change
- ✓ Insert line
- ✓ Delete line
- ✓ Completely different files

### Key Technical Details

**Snake Following:**
```c
static int myers_get_x_after_snake(const char** seq_a, int len_a,
                                   const char** seq_b, int len_b,
                                   int x, int y) {
    while (x < len_a && y < len_b && strcmp(seq_a[x], seq_b[y]) == 0) {
        x++;
        y++;
    }
    return x;
}
```

**Diagonal Bounds:**
- Lower: `-min(d, len_b + (d % 2))`
- Upper: `min(d, len_a + (d % 2))`
- Optimizes to skip irrelevant diagonals

**Path Selection:**
- Choose between vertical (k+1) and horizontal (k-1) moves
- Follow snake (diagonal matches) as far as possible
- Track path for reconstruction

### Memory Management

Careful attention to:
- Dynamic array resizing (doubling strategy)
- Path sharing between diagonals (shared prev pointers)
- Single-pass cleanup of path chain

### Validation Against VSCode

Algorithm structure matches VSCode's TypeScript implementation:
- Same V array indexing
- Same diagonal iteration bounds  
- Same path tracking approach
- Same result format (SequenceDiff arrays)

### Files Created

```
c-diff-core/algorithms/myers.h      # Public API
c-diff-core/algorithms/myers.c      # Implementation
c-diff-core/tests/test_myers.c      # Unit tests
```

### Next Steps

- Step 2: Optimize sequence diffs (join adjacent, filter trivial)
- Step 3: Shift diff boundaries for better human readability
- Eventually replace current diff_core.c with this pipeline

### Performance Characteristics

- Time: O(ND) where N,M are sequence lengths, D is edit distance
- Space: O(N+M) for V and paths arrays
- Best case (identical): O(N) with early diagonal matching
- Worst case (completely different): O(NM) in practice but with good constants

### Lessons Learned

1. **Study the source** - VSCode uses forward-only, not bidirectional
2. **Build incrementally** - Data structures first, then algorithm, then tests
3. **Validate early** - Simple test cases caught issues immediately
4. **Memory discipline** - C requires careful cleanup of dynamic structures
