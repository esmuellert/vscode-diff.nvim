# Character Boundary Scoring Parity Fix

## Date
2025-10-27

## Parity Gap Description
**Issue**: Character boundary scoring lacked category fidelity  
**Impact**: Medium - Affects char-level diff quality for CamelCase, punctuation boundaries  
**Parity**: Was ~2/5, now 5/5 ✓

## Problem Statement

Our C implementation only checked broad word/whitespace cases and returned zero for offsets at sequence edges. VSCode's implementation uses a sophisticated 9-category classification system with weighted scoring.

### What was missing:
1. **No category classification** - Only ad-hoc character type checks
2. **No End-of-sequence handling** - Missing char_code = -1 category
3. **No CamelCase bonus** - Lower→Upper transitions should get +1
4. **Incomplete separator detection** - Only basic punctuation, missing category weights
5. **No symmetric scoring** - Wasn't adding both prev and next category scores

## VSCode Implementation (TypeScript)

Location: `src/vs/editor/common/diff/defaultLinesDiffComputer/linesSliceCharSequence.ts` lines 71-99

```typescript
const enum CharBoundaryCategory {
    WordLower, WordUpper, WordNumber,
    End, Other, Separator, Space,
    LineBreakCR, LineBreakLF
}

const score: Record<CharBoundaryCategory, number> = {
    [CharBoundaryCategory.WordLower]: 0,
    [CharBoundaryCategory.WordUpper]: 0,
    [CharBoundaryCategory.WordNumber]: 0,
    [CharBoundaryCategory.End]: 10,
    [CharBoundaryCategory.Other]: 2,
    [CharBoundaryCategory.Separator]: 30,  // , and ;
    [CharBoundaryCategory.Space]: 3,
    [CharBoundaryCategory.LineBreakCR]: 10,
    [CharBoundaryCategory.LineBreakLF]: 10,
};

function getBoundaryScore(length: number): number {
    const prevCategory = getCategory(prevChar);
    const nextCategory = getCategory(nextChar);
    
    // Special cases
    if (prevCategory === LineBreakCR && nextCategory === LineBreakLF) return 0;
    if (prevCategory === LineBreakLF) return 150;
    
    let score = 0;
    if (prevCategory !== nextCategory) {
        score += 10;
        // CamelCase bonus
        if (prevCategory === WordLower && nextCategory === WordUpper) {
            score += 1;
        }
    }
    
    score += getCategoryBoundaryScore(prevCategory);
    score += getCategoryBoundaryScore(nextCategory);
    return score;
}
```

## Our C Implementation Fix

Location: `c-diff-core/src/sequence.c` lines 232-325

### Added Components:

1. **CharBoundaryCategory enum** (9 categories)
```c
typedef enum {
    CHAR_BOUNDARY_WORD_LOWER,
    CHAR_BOUNDARY_WORD_UPPER,
    CHAR_BOUNDARY_WORD_NUMBER,
    CHAR_BOUNDARY_END,           // char_code = -1
    CHAR_BOUNDARY_OTHER,
    CHAR_BOUNDARY_SEPARATOR,     // , and ;
    CHAR_BOUNDARY_SPACE,
    CHAR_BOUNDARY_LINE_BREAK_CR,
    CHAR_BOUNDARY_LINE_BREAK_LF
} CharBoundaryCategory;
```

2. **get_char_category()** - Classifies characters into categories

3. **get_category_boundary_score()** - Returns score for each category using static array

4. **Rewritten char_seq_get_boundary_score()** - Implements exact VSCode logic:
   - Handles -1 (End) for sequence boundaries
   - Detects CR-LF pairs (return 0 - don't split)
   - After LF returns 150 (highest priority)
   - Category transition bonus (+10)
   - CamelCase bonus (+1 for lower→upper)
   - Symmetric scoring (adds both prev and next category scores)

## Test Coverage

Created comprehensive test suite: `tests/test_char_boundary_categories.c`

**Tests:**
1. CamelCase boundary detection (`fooBar` → detects `foo|Bar` with +1 bonus)
2. Separator priorities (`,` `;` get score 30, `.` gets 2 as "Other")
3. End-of-sequence category (start/end positions get +10)
4. Linebreak handling (\n = 150, \r\n pair = 0)
5. Complete boundary scoring tables for example strings

**All tests pass** ✓

## Impact on Diff Quality

This fix ensures `shift_sequence_diffs` can properly bias character-level diffs toward:
- **CamelCase boundaries** - Prefers breaks between `myVariable|Name`
- **Punctuation** - High priority for commas, semicolons
- **EOF boundaries** - Biases toward start/end of sequences
- **Linebreaks** - Prevents splitting \r\n, prefers breaks after \n

## Parity Status

**Before**: ≈ 2/5 - Basic character type checking, missing category system  
**After**: 5/5 ✓ - Full categorical boundary scoring with 100% VSCode parity

## Files Changed

1. `c-diff-core/src/sequence.c` - Implemented category-based scoring (~90 lines)
2. `c-diff-core/tests/test_char_boundary_categories.c` - Comprehensive test suite (new file)
3. `c-diff-core/Makefile` - Added test-char-boundary target

## References

- VSCode source: `linesSliceCharSequence.ts` lines 71-99
- Midterm evaluation: `dev-docs/advanced-diff/midterm-evaluation-after-fix/advanced-diff-parity-midterm-en.md`
- Implementation plan: `dev-docs/advanced-diff/VSCODE_ADVANCED_DIFF_IMPLEMENTATION_PLAN.md`
