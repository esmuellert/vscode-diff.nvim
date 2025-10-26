# Boundary Scoring and Hashing Parity Gap Analysis

**Date:** 2025-10-25  
**Status:** 🔍 ANALYSIS COMPLETE - Ready for Implementation  
**Related:** Midterm Evaluation - Steps 2-3 Parity Gap

---

## Executive Summary

Our implementation has **two critical parity gaps** with VSCode in Steps 2-3 (line-level optimization):

1. **Boundary Scoring Algorithm Mismatch** - We use blank/brace heuristics; VSCode uses indentation-based scoring
2. **Hash Collision Risk** - We use FNV-1a (collision-prone); VSCode uses perfect hashing (collision-free)

Both gaps affect diff quality and can cause different optimization results compared to VSCode.

---

## Gap 1: Boundary Scoring Algorithm

### What Is Boundary Scoring?

During Step 2 (`shiftSequenceDiffs`), the algorithm tries to shift diff boundaries to "better" positions. The `getBoundaryScore()` function determines what makes a good boundary.

**Example:**
```
Original:  Line 0: int x = 1;
          Line 1: int y = 2;
          Line 2: int z = 3;

Modified:  Line 0: int x = 1;
          Line 1: int y = 99;  // Changed
          Line 2: int z = 3;
```

Initial diff: `seq1[1,2) → seq2[1,2)` (just line 1)

But the algorithm can shift this boundary up or down if neighboring lines are equal. Higher boundary score = preferred position.

### VSCode Implementation

**File:** `src/vs/editor/common/diff/defaultLinesDiffComputer/lineSequence.ts`

```typescript
getBoundaryScore(length: number): number {
    const indentationBefore = length === 0 ? 0 : getIndentation(this.lines[length - 1]);
    const indentationAfter = length === this.lines.length ? 0 : getIndentation(this.lines[length]);
    return 1000 - (indentationBefore + indentationAfter);
}

function getIndentation(str: string): number {
    let i = 0;
    while (i < str.length && (str.charCodeAt(i) === CharCode.Space || str.charCodeAt(i) === CharCode.Tab)) {
        i++;
    }
    return i;
}
```

**Algorithm:**
1. Get indentation of line BEFORE boundary (`length - 1`)
2. Get indentation of line AFTER boundary (`length`)
3. Return `1000 - (indent_before + indent_after)`

**Scoring Philosophy:**
- **Lower indentation = HIGHER score** (better boundary)
- **Higher indentation = LOWER score** (worse boundary)
- Prefers boundaries at less-indented code blocks (e.g., top-level functions over nested blocks)

**Example Scores:**
```
Line 0: "func() {"           // indent=0
Line 1: "    x = 1;"         // indent=4
Line 2: "        y = 2;"     // indent=8
Line 3: "    }"              // indent=4
Line 4: "end()"              // indent=0
```

- Boundary at 0: `1000 - (0 + 0) = 1000` ← Best
- Boundary at 1: `1000 - (0 + 4) = 996`
- Boundary at 2: `1000 - (4 + 8) = 988`
- Boundary at 3: `1000 - (8 + 4) = 988`
- Boundary at 4: `1000 - (4 + 0) = 996`
- Boundary at 5: `1000 - (0 + 0) = 1000` ← Best

### Our Implementation

**File:** `c-diff-core/src/sequence.c`  
**Function:** `line_seq_get_boundary_score()` (lines 104-153)

```c
static int line_seq_get_boundary_score(const ISequence* self, int length) {
    LineSequence* seq = (LineSequence*)self->data;
    
    if (length <= 0 || length > seq->length) {
        return 0;
    }
    
    // Check the line just BEFORE this boundary (length - 1)
    const char* line = seq->lines[length - 1];
    
    // Empty/whitespace-only lines are great boundaries
    bool is_blank = true;
    for (const char* p = line; *p; p++) {
        if (!isspace((unsigned char)*p)) {
            is_blank = false;
            break;
        }
    }
    if (is_blank) {
        return 50;  // High score for blank lines
    }
    
    // Skip leading whitespace to check structural characters
    while (*line && isspace((unsigned char)*line)) {
        line++;
    }
    
    // Structural characters (braces, brackets) are good boundaries
    if (*line == '{' || *line == '}' || 
        *line == '[' || *line == ']' ||
        *line == '(' || *line == ')') {
        
        // Check if rest is mostly whitespace
        const char* rest = line + 1;
        int non_ws = 0;
        while (*rest) {
            if (!isspace((unsigned char)*rest)) {
                non_ws++;
            }
            rest++;
        }
        
        if (non_ws <= 2) {
            return 30;  // Medium-high score for structural lines
        }
    }
    
    // Default: not a particularly good boundary
    return 5;
}
```

**Algorithm:**
1. Check ONLY line BEFORE boundary (`length - 1`)
2. If blank → score 50
3. If starts with structural char ({, }, etc.) → score 30
4. Otherwise → score 5

**Scoring Philosophy:**
- Prefers blank lines and structural characters
- Ignores indentation completely
- Does NOT check line AFTER boundary

### Key Differences

| Aspect | VSCode | Our Implementation |
|--------|--------|-------------------|
| **Lines checked** | Before AND after | Only before |
| **Scoring basis** | Indentation level | Blank/structural chars |
| **Score range** | 0-1000 | 5-50 |
| **Philosophy** | Low indent = better | Blank/braces = better |

### Impact

**Medium Impact** - Affects Step 2 (`shiftSequenceDiffs`):

- Different boundaries may be preferred
- Diffs might shift to different positions
- Final diff output may differ from VSCode

**Scenarios Most Affected:**
- Code with consistent indentation but no blank lines
- Nested blocks where VSCode prefers outer boundaries
- Code without structural characters (e.g., Python without braces)

---

## Gap 2: Hash Collision Risk

### What Is Hashing Used For?

The diff algorithm needs to compare lines quickly. Instead of comparing full strings (slow), it compares hashes (fast). The hash is returned by `getElement()`.

**Critical Requirement:** Different lines should have different hashes (no collisions).

### VSCode Implementation

**File:** `src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts`  
**Lines:** 50-65

```typescript
// Perfect hash using Map - each unique string gets unique ID
const perfectHashes = new Map<string, number>();
function getOrCreateHash(text: string): number {
    let hash = perfectHashes.get(text);
    if (hash === undefined) {
        hash = perfectHashes.size;  // Sequential IDs: 0, 1, 2, ...
        perfectHashes.set(text, hash);
    }
    return hash;
}

const originalLinesHashes = originalLines.map((l) => getOrCreateHash(l.trim()));
const modifiedLinesHashes = modifiedLines.map((l) => getOrCreateHash(l.trim()));

const sequence1 = new LineSequence(originalLinesHashes, originalLines);
const sequence2 = new LineSequence(modifiedLinesHashes, modifiedLines);
```

**Algorithm:**
1. Maintain a `Map<string, number>`
2. For each unique trimmed line, assign sequential ID (0, 1, 2, ...)
3. Same trimmed content → same ID
4. Different trimmed content → different ID (GUARANTEED)

**Properties:**
- ✅ **Perfect hash** - No collisions possible
- ✅ Each unique line gets unique ID
- ✅ Deterministic (same input → same output)
- ✅ Hash is just sequential number (0, 1, 2, 3, ...)

### Our Implementation

**File:** `c-diff-core/src/sequence.c`  
**Function:** `hash_trimmed_string()` (lines 43-64)

```c
static uint32_t hash_trimmed_string(const char* str) {
    if (!str) return 0;
    
    // Skip leading whitespace
    while (*str && isspace((unsigned char)*str)) {
        str++;
    }
    
    // Find end (non-whitespace)
    const char* end = str + strlen(str);
    while (end > str && isspace((unsigned char)*(end - 1))) {
        end--;
    }
    
    // Hash the trimmed portion using FNV-1a
    uint32_t hash = 2166136261u;
    for (const char* p = str; p < end; p++) {
        hash ^= (uint32_t)(unsigned char)(*p);
        hash *= 16777619u;
    }
    return hash;
}
```

**Algorithm:**
1. Trim whitespace from both ends
2. Apply FNV-1a hash algorithm
3. Return 32-bit hash value

**Properties:**
- ❌ **Not a perfect hash** - Collisions ARE possible
- ❌ Different strings might produce same hash
- ✅ Fast computation
- ✅ Good distribution (collisions are rare but not zero)

### Key Differences

| Aspect | VSCode | Our Implementation |
|--------|--------|-------------------|
| **Collision probability** | 0% (impossible) | Non-zero (rare but possible) |
| **Hash type** | Sequential IDs | FNV-1a hash values |
| **Data structure** | Map<string, ID> | Direct hash computation |
| **Memory** | Stores map | No additional storage |

### Impact

**Medium-High Impact** - Affects Steps 2-3:

**When collision occurs:**
1. Algorithm thinks two different lines are "equal" (same hash)
2. Diffs might be incorrectly merged/optimized
3. Wrong output compared to VSCode

**Probability Analysis:**
- FNV-1a has good distribution
- Collisions are rare for typical code
- But on large files (1000+ lines), probability increases
- **VSCode: 0% collision guaranteed**
- **Our code: Non-zero collision risk**

**Example Collision Scenario:**
```c
// Suppose these two lines happen to hash to same value (unlikely but possible)
"int x = 42;" → hash = 0x1234ABCD
"float y = 3.14;" → hash = 0x1234ABCD  // Collision!

// Algorithm will treat them as equal during diff computation
// Could lead to incorrect diff merging
```

---

## Files and Functions to Modify

### Gap 1: Boundary Scoring Fix

**Files to modify:**
1. `c-diff-core/src/sequence.c`
   - **Function:** `line_seq_get_boundary_score()` (lines 104-153)

**Required changes:**
```c
// NEW implementation (VSCode parity)
static int line_seq_get_boundary_score(const ISequence* self, int length) {
    LineSequence* seq = (LineSequence*)self->data;
    
    // Edge cases
    if (length < 0 || length > seq->length) {
        return 0;
    }
    
    // Get indentation BEFORE boundary
    int indent_before = 0;
    if (length > 0) {
        indent_before = get_indentation(seq->lines[length - 1]);
    }
    
    // Get indentation AFTER boundary
    int indent_after = 0;
    if (length < seq->length) {
        indent_after = get_indentation(seq->lines[length]);
    }
    
    // VSCode formula: 1000 - (indent_before + indent_after)
    return 1000 - (indent_before + indent_after);
}

// Helper function (new)
static int get_indentation(const char* line) {
    int i = 0;
    while (line[i] == ' ' || line[i] == '\t') {
        i++;
    }
    return i;
}
```

**Testing:**
- Update `test_line_optimization.c` if any tests depend on specific boundary scores
- Add new test cases for indentation-based boundary scoring

---

### Gap 2: Perfect Hash Fix

**Files to modify:**
1. `c-diff-core/include/sequence.h`
   - **Struct:** `LineSequence` - Add hash map or ID array

2. `c-diff-core/src/sequence.c`
   - **Function:** `line_sequence_create()` - Build perfect hash map
   - **Function:** `line_seq_get_element()` - Return perfect hash ID
   - **Function:** `line_seq_destroy()` - Clean up hash map
   - **Remove:** `hash_trimmed_string()` - No longer needed (or keep for other uses)

**Implementation Options:**

#### Option 1: Map-Based Perfect Hash (Closest to VSCode)

**Pros:**
- Exact VSCode behavior
- Minimal memory overhead
- Handles duplicates naturally

**Cons:**
- Need to implement/integrate hash map
- More complex code

**Changes:**
```c
// In sequence.h
typedef struct {
    const char** lines;
    uint32_t* line_ids;        // NEW: Perfect hash IDs
    int length;
    bool ignore_whitespace;
    void* hash_map;            // NEW: Map for string→ID lookup
} LineSequence;

// In sequence.c
ISequence* line_sequence_create(const char** lines, int length, bool ignore_whitespace) {
    // 1. Create hash map
    // 2. For each line:
    //    - Trim it
    //    - Check if trimmed string exists in map
    //    - If yes: reuse existing ID
    //    - If no: assign new sequential ID
    // 3. Store IDs in line_ids array
    // 4. getElement() returns line_ids[offset]
}
```

#### Option 2: Pre-Assigned IDs (Simpler, More Memory)

**Pros:**
- Simpler implementation
- No hash map needed
- Fast lookup

**Cons:**
- Higher memory usage (stores trimmed strings)
- Need to store unique trimmed lines

**Changes:**
```c
// In sequence.h
typedef struct {
    const char** lines;
    char** unique_trimmed;     // NEW: Unique trimmed lines
    uint32_t* line_to_id;      // NEW: Map from line index to unique ID
    int length;
    int unique_count;          // NEW: Number of unique lines
    bool ignore_whitespace;
} LineSequence;

// In sequence.c
ISequence* line_sequence_create(const char** lines, int length, bool ignore_whitespace) {
    // 1. Allocate arrays
    // 2. For each line:
    //    - Trim it
    //    - Linear search in unique_trimmed[] for match
    //    - If found: line_to_id[i] = existing_id
    //    - If not: Add to unique_trimmed[], line_to_id[i] = unique_count++
    // 3. getElement() returns line_to_id[offset]
}
```

#### Recommended: Option 1 with Simple Hash Table

Use a simple hash table implementation (not FNV-1a for hash, but for table structure):
- Array of buckets (linked lists)
- String comparison for exact match
- Sequential ID assignment

This balances VSCode parity with implementation simplicity.

**Testing:**
- Add collision regression tests
- Test with duplicate lines
- Test with large files (stress test)
- Verify IDs are consistent

---

## Recommended Implementation Order

### Phase 1: Boundary Scoring (Easier)
1. ✅ Add `get_indentation()` helper function
2. ✅ Rewrite `line_seq_get_boundary_score()`
3. ✅ Run existing tests - verify they still pass
4. ✅ Add new tests for indentation-based scoring
5. ✅ Document changes

**Estimated effort:** 2-3 hours

### Phase 2: Perfect Hash (More Complex)
1. ✅ Design hash map structure (or choose library)
2. ✅ Update `LineSequence` struct in `sequence.h`
3. ✅ Modify `line_sequence_create()` to build perfect hash
4. ✅ Update `line_seq_get_element()` to return IDs
5. ✅ Update `line_seq_destroy()` to clean up hash map
6. ✅ Run all tests - verify correctness
7. ✅ Add collision regression tests
8. ✅ Document changes

**Estimated effort:** 6-8 hours

### Phase 3: Validation
1. ✅ Compare outputs with VSCode on various test files
2. ✅ Verify boundary shifting matches VSCode
3. ✅ Verify no hash collisions affect results
4. ✅ Update parity documentation

**Estimated effort:** 2-3 hours

---

## Current Parity Status

### Before Fixes
- **Step 2-3 Parity:** 0.5/1.0 (partial)
- **Boundary scoring:** ❌ Different algorithm
- **Hashing:** ❌ Collision-prone FNV-1a

### After Fixes
- **Step 2-3 Parity:** ~0.9/1.0 (near-complete)
- **Boundary scoring:** ✅ Matches VSCode indentation-based algorithm
- **Hashing:** ✅ Perfect hash, collision-free

**Remaining gaps after fixes:**
- Character-level whitespace tracking (Step 4)
- Word extension handling (Step 4)
- Whitespace-only rescanning (Step 4)

---

## Validation Strategy

### Test Cases for Boundary Scoring

```c
// Test 1: Nested blocks - prefer outer boundary
const char* lines1[] = {
    "func() {",        // indent=0
    "    if (x) {",    // indent=4
    "        y = 1;",  // indent=8 ← diff here
    "    }",           // indent=4
    "}"                // indent=0
};

// Boundary at line 1 (indent=0+4=4) → score=996
// Boundary at line 2 (indent=4+8=12) → score=988
// Should prefer line 1 boundary
```

### Test Cases for Perfect Hash

```c
// Test 1: Duplicate lines should get same ID
const char* lines2[] = {
    "int x = 1;",
    "int y = 2;",
    "int x = 1;",  // Same as line 0 → should get same ID
};

// Test 2: Different lines should get different IDs
const char* lines3[] = {
    "int x = 42;",
    "float y = 3.14;",
};
// Even if FNV-1a would collide, perfect hash should give different IDs

// Test 3: Trimming should work
const char* lines4[] = {
    "  int x = 1;  ",
    "int x = 1;",
};
// Both should get same ID after trimming
```

---

## Conclusion

These two parity gaps are **well-understood and ready for implementation**:

1. **Boundary Scoring** - Straightforward function rewrite
2. **Perfect Hash** - Requires hash map but clear path forward

Both gaps have **medium impact** on diff quality. Fixing them will bring Steps 2-3 to ~90% parity with VSCode.

**Next Action:** Implement Phase 1 (Boundary Scoring) first, then Phase 2 (Perfect Hash).
