# DP Scoring Callback - Parity Gap Analysis

**Date:** 2025-10-26  
**Status:** ❌ MISSING - This is a REAL parity gap that must be fixed
**Impact:** Whitespace-only changes on small files produce different diffs than VSCode

## Summary

**This is NOT an intentional deferral - it's an accidental omission.**

When we implemented the DP algorithm (commit `f1cd35e`), we correctly:
1. ✅ Added the `EqualityScoreFn` infrastructure 
2. ✅ Implemented the DP algorithm to accept and use the scoring callback
3. ✅ Documented the scoring callback in the implementation notes

**BUT we failed to actually wire it up** in the dispatcher:

```c
// Current code - WRONG, passes NULL
if (total < 1700) {
    return myers_dp_diff_algorithm(seq1, seq2, timeout_ms, hit_timeout, NULL, NULL);
}
```

**Should be:**
```c
// Need to pass the actual scoring function!
if (total < 1700) {
    return myers_dp_diff_algorithm(seq1, seq2, timeout_ms, hit_timeout, 
                                   line_equality_score, line_data);
}
```

## Why This Matters

### VSCode's Behavior (Small Files < 1700 lines)

When VSCode calls the DP algorithm for line-level diffs, it provides this scoring function:

```typescript
(offset1, offset2) =>
    originalLines[offset1] === modifiedLines[offset2]
        ? modifiedLines[offset2].length === 0
            ? 0.1     // Empty lines get low score
            : 1 + Math.log(1 + modifiedLines[offset2].length)  // Longer lines preferred
        : 0.99        // Nearly-equal lines (whitespace diff) still get credit
```

### Our Current Behavior

We pass `NULL` for the scoring function, so the DP algorithm uses this default:

```c
extendedSeqScore += (equalityScore ? equalityScore(s1, s2) : 1);
//                                                             ^^^
//                                                    Always 1.0 for us
```

### The Divergence

**Scenario:** Small file (< 1700 lines) with whitespace-only changes

**VSCode:**
- Empty line changed to `    ` (4 spaces): Uses score 0.99 (nearly equal)
- Line "hello" changed to "hello world": Uses score 1 + log(12) ≈ 3.48
- Prefers aligning longer, more meaningful lines
- Results in better quality diffs

**Our Implementation:**
- All equal lines get score = 1.0
- No preference for longer vs empty lines
- Different alignment choices → different diff output

## Root Cause Analysis

### When Was This Introduced?

**Commit `f1cd35e` - "Implement dp in myers"** (2025-10-25)

From the original implementation doc at that commit:
```
## Remaining Parity Work

- Line-level scoring hook: VSCode forwards a weighting callback when it 
  selects the DP path so that trimmed-equal lines with different whitespace 
  still prefer alignment. The C dispatcher currently calls 
  myers_dp_diff_algorithm(..., NULL, NULL), so whitespace-only edits on 
  short files will not match VSCode's behavior yet.
```

**The doc explicitly stated this was missing!** So why wasn't it implemented?

### Why Was It Left Out?

Looking at the git history, there's no follow-up commit that added the scoring callback. The sequence was:

1. `f1cd35e` - Implement DP (with TODO in doc)
2. `0fc2639` - Update DP doc (kept the same TODO)
3. `d9a57eb` - Hash and boundary scoring gap explained
4. `b23ac86` - Fix hash collision and boundary scoring issue
5. **No commit that added the scoring callback**

**Conclusion:** This was documented as "remaining work" but never actually completed. It's not an intentional deferral for a future step - it's simply unfinished work from the DP implementation.

## Why It Wasn't Caught

### During Implementation
The DP implementation focused on:
- ✅ Algorithm correctness (3 matrices, backtracking)
- ✅ Size-based selection (1700 threshold)
- ✅ Infrastructure (EqualityScoreFn typedef)

But **didn't complete the integration** by wiring up the actual callback.

### During Testing
Our test suite (test_dp_algorithm.c) verified:
- ✅ DP vs O(ND) produce same results
- ✅ Threshold selection works
- ✅ Scoring function infrastructure exists

But **didn't test with actual whitespace-sensitive scenarios** that would reveal the difference.

### During Review
The docs said "remaining work" but this was interpreted as:
- ❌ WRONG: "Future feature for later steps"
- ✅ CORRECT: "Unfinished work that should be completed now"

## VSCode Parity Status

### Claimed in Docs
> "Step 1 Parity: ~0.8/1.0 (still partial)"

### Reality
**This percentage is correct**, but the gap is not acceptable:

- ✅ DP algorithm implementation: 100% (all matrices, backtracking correct)
- ✅ O(ND) algorithm: 100% 
- ✅ Threshold selection: 100%
- ✅ Infrastructure: 100% (callback typedef exists)
- ❌ **Actual scoring callback usage: 0%** ← THIS IS THE GAP

## What Needs to Be Fixed

### 1. Implement Line Equality Scoring Function

```c
// In myers.c or sequence.c
static double line_equality_score(int offset1, int offset2, void* user_data) {
    LineEqualityScoreData* data = (LineEqualityScoreData*)user_data;
    const char* line1 = data->lines1[offset1];
    const char* line2 = data->lines2[offset2];
    
    // If lines are exactly equal (same content)
    if (strcmp(line1, line2) == 0) {
        // Empty line gets low score
        if (strlen(line2) == 0) {
            return 0.1;
        }
        // Longer lines preferred (same formula as VSCode)
        return 1.0 + log(1.0 + strlen(line2));
    }
    
    // Lines differ - check if only whitespace differs
    // This requires comparing trimmed versions (hash already matches if trimmed equal)
    // For now, if hash matches but content differs, it's whitespace difference
    return 0.99;  // Nearly equal (whitespace-only difference)
}
```

### 2. Pass Scoring Data Structure

```c
typedef struct {
    const char** lines1;
    const char** lines2;
    // Could add hash_map here if needed for trimmed comparison
} LineEqualityScoreData;
```

### 3. Wire Up in Dispatcher

Modify `myers_diff_algorithm()`:

```c
if (total < 1700) {
    // For line-level sequences, need to extract original line strings
    // This requires LineSequence to provide access to original data
    // For now, only char sequences use NULL (they don't need scoring)
    
    // TODO: Extract line data from seq1/seq2 if they're LineSequence instances
    // LineEqualityScoreData score_data = { ... };
    // return myers_dp_diff_algorithm(seq1, seq2, timeout_ms, hit_timeout,
    //                                line_equality_score, &score_data);
    
    // For now: still NULL, but at least we know what's needed
    return myers_dp_diff_algorithm(seq1, seq2, timeout_ms, hit_timeout, NULL, NULL);
}
```

### 4. Design Challenge: Type Erasure

**The problem:** Our `ISequence` interface is type-erased. The dispatcher doesn't know if it's receiving:
- LineSequence (needs scoring callback)
- CharSequence (doesn't need scoring)

**Possible solutions:**

**Option A:** Add a method to ISequence to get scoring callback
```c
typedef struct {
    // ... existing methods ...
    EqualityScoreFn (*getScoringFn)(const ISequence* self);
    void* (*getScoringData)(const ISequence* self);
} ISequence;
```

**Option B:** Pass scoring function from caller
```c
// Make myers_diff_algorithm accept optional scoring
SequenceDiffArray* myers_diff_algorithm(
    const ISequence* seq1, const ISequence* seq2,
    int timeout_ms, bool* hit_timeout,
    EqualityScoreFn score_fn, void* user_data);  // New params
```

**Option C:** Have two separate entry points
```c
SequenceDiffArray* myers_diff_lines_with_scoring(...);  // For line-level
SequenceDiffArray* myers_diff_chars(...);               // For char-level
```

## Testing Requirements

Once implemented, we need tests that verify:

1. **Empty line scoring**
   ```c
   // Line changed from "" to "    "
   // Should prefer aligning non-empty lines elsewhere
   ```

2. **Length-based preference**
   ```c
   // Short line "a" vs long line "function doSomething() {"
   // Should prefer aligning the longer line
   ```

3. **Whitespace-only changes**
   ```c
   // Line "hello" vs "hello " (trailing space)
   // Should still align (score 0.99) but note the difference
   ```

## Conclusion

**This is a BUG, not a deferred feature.**

- ✅ We have the infrastructure (EqualityScoreFn typedef)
- ✅ We have the DP implementation that uses it
- ✅ We documented what's needed (VSCode's formula)
- ❌ **We never actually wired it up**

**Why it happened:**
1. The DP implementation PR was large and focused on core algorithm
2. The "remaining work" section was documented but not tracked as required
3. Follow-up work focused on hash/boundary scoring (different gap)
4. No one went back to complete the DP callback integration

**Priority:** HIGH - This affects all small files (< 1700 lines) with whitespace changes, which is a common scenario in real-world usage.

**Effort:** MEDIUM - Infrastructure exists, just needs wiring and data plumbing through the type-erased interface.

**Next Steps:** Design the cleanest way to pass line data through ISequence abstraction, implement the scoring function, and add comprehensive tests.
