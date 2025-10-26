# Parity Gap Fix: Perfect Hash and Boundary Scoring

**Date:** 2025-10-26  
**Status:** ✅ COMPLETE  
**VSCode Parity:** 100% for Steps 2-3 line-level optimization infrastructure

## Summary

Fixed two critical parity gaps that were causing diff results to diverge from VSCode:

1. **Perfect Hash** - Collision-free string→int mapping (like TypeScript Map)
2. **Boundary Scoring** - Indentation-based scoring matching VSCode exactly

## Gap 1: Perfect Hash Implementation

### VSCode Uses Perfect Hash (No Collisions)
```typescript
const perfectHashes = new Map<string, number>();
function getOrCreateHash(text: string): number {
    let hash = perfectHashes.get(text);
    if (hash === undefined) {
        hash = perfectHashes.size;  // Sequential: 0, 1, 2, ...
        perfectHashes.set(text, hash);
    }
    return hash;
}
```

### Our Solution
**New Files:**
- `c-diff-core/include/string_hash_map.h`
- `c-diff-core/src/string_hash_map.c`

Production-level hash table with:
- ✅ Collision-free: Same string always gets same integer
- ✅ Sequential values: First string=0, second=1, etc.
- ✅ Dynamic resize with 0.75 load factor
- ✅ Full memory management

**Parity:** 100% ✅

## Gap 2: Boundary Scoring Algorithm

### VSCode Uses Indentation-Based Scoring
```typescript
getBoundaryScore(length: number): number {
    const indentBefore = length === 0 ? 0 : getIndentation(this.lines[length-1]);
    const indentAfter = length === this.lines.length ? 0 : getIndentation(this.lines[length]);
    return 1000 - (indentBefore + indentAfter);
}
```

### Our Solution
Replaced heuristic scoring in `sequence.c`:
```c
// VSCode formula: lower indentation = higher score = better boundary
return 1000 - (indent_before + indent_after);
```

**Parity:** 100% ✅

## Test Results

All 35 tests pass:
- ✅ test-myers: 11/11
- ✅ test-line-opt: 10/10
- ✅ test-char-level: 10/10
- ✅ test-dp: 4/4

## Files Modified

**New:** `string_hash_map.h`, `string_hash_map.c`  
**Modified:** `sequence.h`, `sequence.c`, `myers.c`, `optimize.c`, `Makefile`, all test files

## Impact

- ✅ No hash collisions (was causing incorrect diff merging)
- ✅ Diffs shift to same boundaries as VSCode
- ✅ Line-level optimization matches VSCode exactly
