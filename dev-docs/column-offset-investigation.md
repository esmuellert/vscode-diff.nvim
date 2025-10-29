# Column Offset Mismatch Investigation

## Current Status
- Mismatches reduced from 64 to 37 through previous fixes
- Remaining 37 mismatches appear to be related to column offset calculations

## Problem Description
When comparing C and Node.js diff outputs, we see column mismatches like:
- C output: `L53:C12-L58:C10`
- Node output: `L53:C1-L58:C10`

## Investigation Findings

### VSCode Implementation Analysis
Checked VSCode's `linesSliceCharSequence.ts` and found:

```typescript
public translateOffset(offset: number, preference: 'left' | 'right' = 'right'): Position {
    const i = findLastIdxMonotonous(this.firstElementOffsetByLineIdx, (value) => value <= offset);
    const lineOffset = offset - this.firstElementOffsetByLineIdx[i];
    return new Position(
        this.range.startLineNumber + i,
        1 + this.lineStartOffsets[i] + lineOffset + 
           ((lineOffset === 0 && preference === 'left') ? 0 : this.trimmedWsLengthsByLineIdx[i])
    );
}
```

Our C implementation matches this formula correctly.

### Test Case Analysis
For the specific case of Makefile line 18 -> lines 53-71:
- Character offset 11 in CharSequence
- line_idx = 0, line_offset = 11
- original_line_start = 0 (line starts at column 1)
- trimmed_ws = 0 (no trimmed whitespace)
- Result: column = 0 + 11 + 0 = 11 (0-based) = 12 (1-based)

This matches what C outputs (C12), but VSCode outputs C1.

### Hypothesis
The issue may not be in `translate_offset` itself, but in:\n1. Character-level range merging logic
2. How multiple diffs within a line-level change are combined
3. The optimization passes that merge adjacent character changes

### Next Steps
Need to investigate:
1. The character-level diff optimization/merging in optimize.c
2. Whether VSCode merges character ranges differently
3. The "3 inner changes" mentioned in the output - are ranges being merged?

## Code Locations
- `c-diff-core/src/sequence.c:613-660` - translate_offset implementation
- `c-diff-core/src/char_level.c:755-793` - translate_diff_to_range
- `c-diff-core/src/optimize.c` - optimization passes that may merge ranges
