/**
 * Step 2 & 3: Diff Optimization - FULL VSCODE PARITY
 * 
 * Implements VSCode's heuristic sequence optimizations using ISequence infrastructure:
 * 1. joinSequenceDiffsByShifting() - Called twice for better results
 * 2. shiftSequenceDiffs() - Shift to better boundaries using getBoundaryScore()
 * 3. removeShortMatches() - Join diffs separated by ≤2 lines
 * 
 * REUSED BY: Step 4 (character-level optimization uses same functions)
 * 
 * VSCode Reference:
 * src/vs/editor/common/diff/defaultLinesDiffComputer/heuristicSequenceOptimizations.ts
 */

#include "../include/optimize.h"
#include "../include/sequence.h"
#include "../include/types.h"
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

// Forward declarations
static SequenceDiffArray* join_sequence_diffs_by_shifting(
    const ISequence* seq1, const ISequence* seq2, SequenceDiffArray* diffs);
static SequenceDiffArray* shift_sequence_diffs(
    const ISequence* seq1, const ISequence* seq2, SequenceDiffArray* diffs);
static SequenceDiff shift_diff_to_better_position(
    SequenceDiff diff, const ISequence* seq1, const ISequence* seq2,
    int seq1_valid_start, int seq1_valid_end,
    int seq2_valid_start, int seq2_valid_end);

// Helper: Min/Max functions
static inline int min_int(int a, int b) { return a < b ? a : b; }
static inline int max_int(int a, int b) { return a > b ? a : b; }

/**
 * joinSequenceDiffsByShifting() - VSCode Parity
 * 
 * Fixes issues like:
 *   import { Baz, Bar } from "foo";
 *   import { Baz, Bar, Foo } from "foo";
 * 
 * Computed diff: [{Add "," after Bar}, {Add "Foo " after space}]
 * Improved diff: [{Add ", Foo" after Bar}]
 * 
 * Algorithm:
 * 1. Move diffs left as much as possible and join if they meet
 * 2. Move diffs right and join if they meet
 * 
 * Only works for insertion/deletion diffs (one range is empty)
 */
static SequenceDiffArray* join_sequence_diffs_by_shifting(
    const ISequence* seq1, const ISequence* seq2, SequenceDiffArray* diffs) {
    
    if (diffs->count == 0) {
        return diffs;
    }
    
    int len1 = seq1->getLength(seq1);
    int len2 = seq2->getLength(seq2);
    
    // Result array for first pass (move left)
    SequenceDiff* result1 = (SequenceDiff*)malloc(diffs->count * sizeof(SequenceDiff));
    int result1_count = 0;
    
    result1[result1_count++] = diffs->diffs[0];
    
    // First pass: Move all diffs left and join if possible
    for (int i = 1; i < diffs->count; i++) {
        SequenceDiff* prev_result = &result1[result1_count - 1];
        SequenceDiff cur = diffs->diffs[i];
        
        // Check if this is an insertion or deletion (one range is empty)
        bool is_insert_or_delete = (cur.seq1_start == cur.seq1_end) || 
                                   (cur.seq2_start == cur.seq2_end);
        
        if (is_insert_or_delete) {
            int length = cur.seq1_start - prev_result->seq1_end;
            int d;
            
            // Try to shift left as much as possible
            for (d = 1; d <= length; d++) {
                int pos1_start = cur.seq1_start - d;
                int pos1_end = cur.seq1_end - d;
                int pos2_start = cur.seq2_start - d;
                int pos2_end = cur.seq2_end - d;
                
                if (pos1_start < 0 || pos1_end < 0 || pos2_start < 0 || pos2_end < 0) {
                    break;
                }
                if (pos1_start >= len1 || pos1_end > len1 || pos2_start >= len2 || pos2_end > len2) {
                    break;
                }
                
                // Check if shifted position still matches
                if (seq1->getElement(seq1, pos1_start) != seq1->getElement(seq1, pos1_end) ||
                    seq2->getElement(seq2, pos2_start) != seq2->getElement(seq2, pos2_end)) {
                    break;
                }
            }
            d--;
            
            if (d == length) {
                // Can merge with previous diff
                prev_result->seq1_end = cur.seq1_end - length;
                prev_result->seq2_end = cur.seq2_end - length;
                continue;
            }
            
            // Shift by d positions
            cur.seq1_start -= d;
            cur.seq1_end -= d;
            cur.seq2_start -= d;
            cur.seq2_end -= d;
        }
        
        result1[result1_count++] = cur;
    }
    
    // Second pass: Move all diffs right and join if possible
    SequenceDiff* result2 = (SequenceDiff*)malloc(result1_count * sizeof(SequenceDiff));
    int result2_count = 0;
    
    for (int i = 0; i < result1_count - 1; i++) {
        SequenceDiff cur = result1[i];
        SequenceDiff* next_result = &result1[i + 1];
        
        bool is_insert_or_delete = (cur.seq1_start == cur.seq1_end) || 
                                   (cur.seq2_start == cur.seq2_end);
        
        if (is_insert_or_delete) {
            int length = next_result->seq1_start - cur.seq1_end;
            int d;
            
            // Try to shift right as much as possible
            for (d = 0; d < length; d++) {
                int pos1_start = cur.seq1_start + d;
                int pos1_end = cur.seq1_end + d;
                int pos2_start = cur.seq2_start + d;
                int pos2_end = cur.seq2_end + d;
                
                if (pos1_start >= len1 || pos1_end > len1 || pos2_start >= len2 || pos2_end > len2) {
                    break;
                }
                
                // Use isStronglyEqual for exact comparison
                if (!seq1->isStronglyEqual(seq1, pos1_start, pos1_end) ||
                    !seq2->isStronglyEqual(seq2, pos2_start, pos2_end)) {
                    break;
                }
            }
            
            if (d == length) {
                // Can merge with next diff
                next_result->seq1_start = cur.seq1_start + length;
                next_result->seq2_start = cur.seq2_start + length;
                continue;
            }
            
            if (d > 0) {
                cur.seq1_start += d;
                cur.seq1_end += d;
                cur.seq2_start += d;
                cur.seq2_end += d;
            }
        }
        
        result2[result2_count++] = cur;
    }
    
    // Add last element
    if (result1_count > 0) {
        result2[result2_count++] = result1[result1_count - 1];
    }
    
    // Update original array
    free(diffs->diffs);
    diffs->diffs = result2;
    diffs->count = result2_count;
    
    free(result1);
    
    return diffs;
}

/**
 * shiftDiffToBetterPosition() - VSCode Parity
 * 
 * For insertion/deletion diffs, find the best position by boundary scoring.
 * Shifts the diff within valid range to maximize boundary scores.
 */
static SequenceDiff shift_diff_to_better_position(
    SequenceDiff diff, const ISequence* seq1, const ISequence* seq2,
    int seq1_valid_start, int seq1_valid_end,
    int seq2_valid_start, int seq2_valid_end) {
    
    const int MAX_SHIFT_LIMIT = 100;  // Performance limit
    
    // Calculate how far we can shift left (before)
    int delta_before = 1;
    while (diff.seq1_start - delta_before >= seq1_valid_start &&
           diff.seq2_start - delta_before >= seq2_valid_start &&
           seq2->isStronglyEqual(seq2, diff.seq2_start - delta_before, 
                                diff.seq2_end - delta_before) &&
           delta_before < MAX_SHIFT_LIMIT) {
        delta_before++;
    }
    delta_before--;
    
    // Calculate how far we can shift right (after)
    int delta_after = 0;
    while (diff.seq1_start + delta_after < seq1_valid_end &&
           diff.seq2_end + delta_after < seq2_valid_end &&
           seq2->isStronglyEqual(seq2, diff.seq2_start + delta_after,
                                diff.seq2_end + delta_after) &&
           delta_after < MAX_SHIFT_LIMIT) {
        delta_after++;
    }
    
    if (delta_before == 0 && delta_after == 0) {
        return diff;
    }
    
    // Find best position by boundary score
    int best_delta = 0;
    int best_score = -1;
    
    if (seq1->getBoundaryScore && seq2->getBoundaryScore) {
        for (int delta = -delta_before; delta <= delta_after; delta++) {
            int seq2_offset_start = diff.seq2_start + delta;
            int seq2_offset_end = diff.seq2_end + delta;
            int seq1_offset = diff.seq1_start + delta;
            
            int score = seq1->getBoundaryScore(seq1, seq1_offset) +
                       seq2->getBoundaryScore(seq2, seq2_offset_start) +
                       seq2->getBoundaryScore(seq2, seq2_offset_end);
            
            if (score > best_score) {
                best_score = score;
                best_delta = delta;
            }
        }
    }
    
    // Apply best delta
    diff.seq1_start += best_delta;
    diff.seq1_end += best_delta;
    diff.seq2_start += best_delta;
    diff.seq2_end += best_delta;
    
    return diff;
}

/**
 * shiftSequenceDiffs() - VSCode Parity
 * 
 * Aligns character-level diffs at whitespace/word boundaries using boundary scoring.
 * Only applies to insertion/deletion diffs (one range is empty).
 */
static SequenceDiffArray* shift_sequence_diffs(
    const ISequence* seq1, const ISequence* seq2, SequenceDiffArray* diffs) {
    
    // Skip if sequences don't support boundary scoring
    if (!seq1->getBoundaryScore || !seq2->getBoundaryScore) {
        return diffs;
    }
    
    int len1 = seq1->getLength(seq1);
    int len2 = seq2->getLength(seq2);
    
    for (int i = 0; i < diffs->count; i++) {
        SequenceDiff* prev_diff = (i > 0) ? &diffs->diffs[i - 1] : NULL;
        SequenceDiff diff = diffs->diffs[i];
        SequenceDiff* next_diff = (i + 1 < diffs->count) ? &diffs->diffs[i + 1] : NULL;
        
        // Calculate valid range (don't touch adjacent diffs)
        int seq1_valid_start = prev_diff ? (prev_diff->seq1_end + 1) : 0;
        int seq1_valid_end = next_diff ? (next_diff->seq1_start - 1) : len1;
        int seq2_valid_start = prev_diff ? (prev_diff->seq2_end + 1) : 0;
        int seq2_valid_end = next_diff ? (next_diff->seq2_start - 1) : len2;
        
        // Only shift insertions or deletions
        if (diff.seq1_start == diff.seq1_end) {
            // Insertion in seq2
            diffs->diffs[i] = shift_diff_to_better_position(
                diff, seq1, seq2, seq1_valid_start, seq1_valid_end,
                seq2_valid_start, seq2_valid_end);
        } else if (diff.seq2_start == diff.seq2_end) {
            // Deletion from seq1 (swap and shift)
            SequenceDiff swapped = {
                .seq1_start = diff.seq2_start,
                .seq1_end = diff.seq2_end,
                .seq2_start = diff.seq1_start,
                .seq2_end = diff.seq1_end
            };
            
            SequenceDiff shifted = shift_diff_to_better_position(
                swapped, seq2, seq1, seq2_valid_start, seq2_valid_end,
                seq1_valid_start, seq1_valid_end);
            
            // Swap back
            diffs->diffs[i].seq1_start = shifted.seq2_start;
            diffs->diffs[i].seq1_end = shifted.seq2_end;
            diffs->diffs[i].seq2_start = shifted.seq1_start;
            diffs->diffs[i].seq2_end = shifted.seq1_end;
        }
    }
    
    return diffs;
}

/**
 * optimizeSequenceDiffs() - Main Optimization Entry Point (VSCode Parity - Step 2 ONLY!)
 * 
 * VSCode's algorithm:
 * 1. joinSequenceDiffsByShifting() - called TWICE for better results
 * 2. shiftSequenceDiffs() - align at good boundaries
 * 
 * NOTE: In VSCode, removeShortMatches() (Step 3) is called SEPARATELY!
 * We must NOT bundle it here to match VSCode's architecture.
 * 
 * REUSED BY: Step 4 (character-level optimization)
 */
SequenceDiffArray* optimize_sequence_diffs(const ISequence* seq1, const ISequence* seq2, 
                                          SequenceDiffArray* diffs) {
    if (!seq1 || !seq2 || !diffs) {
        return diffs;
    }
    
    // Join by shifting (called twice per VSCode)
    diffs = join_sequence_diffs_by_shifting(seq1, seq2, diffs);
    diffs = join_sequence_diffs_by_shifting(seq1, seq2, diffs);
    
    // Shift to better boundaries
    diffs = shift_sequence_diffs(seq1, seq2, diffs);
    
    // DO NOT call remove_short_matches here!
    // It's Step 3, called separately by the main diff computer.
    
    return diffs;
}

/**
 * removeShortMatches() - VSCode Parity
 * 
 * Joins diffs separated by short matching regions (≤2 lines).
 * 
 * VSCode algorithm from heuristicSequenceOptimizations.ts:
 * "if (s.seq1Range.start - last.seq1Range.endExclusive <= 2 ||
 *      s.seq2Range.start - last.seq2Range.endExclusive <= 2)"
 * 
 * REUSED BY: Step 4 (character-level short match removal)
 */
SequenceDiffArray* remove_short_matches(const ISequence* seq1 __attribute__((unused)),
                                       const ISequence* seq2 __attribute__((unused)),
                                       SequenceDiffArray* diffs) {
    if (!diffs || diffs->count == 0) {
        return diffs;
    }
    
    SequenceDiff* result = (SequenceDiff*)malloc(diffs->count * sizeof(SequenceDiff));
    int result_count = 0;
    
    for (int i = 0; i < diffs->count; i++) {
        if (result_count == 0) {
            result[result_count++] = diffs->diffs[i];
        } else {
            SequenceDiff* last = &result[result_count - 1];
            SequenceDiff s = diffs->diffs[i];
            
            int gap1 = s.seq1_start - last->seq1_end;
            int gap2 = s.seq2_start - last->seq2_end;
            
            // VSCode: join if gap ≤ 2 in EITHER sequence
            if (gap1 <= 2 || gap2 <= 2) {
                // Join with last
                last->seq1_end = s.seq1_end;
                last->seq2_end = s.seq2_end;
            } else {
                result[result_count++] = s;
            }
        }
    }
    
    // Update original array
    free(diffs->diffs);
    diffs->diffs = result;
    diffs->count = result_count;
    
    return diffs;
}

/**
 * removeVeryShortMatchingLinesBetweenDiffs() - VSCode Parity (LINE-LEVEL Step 3)
 * 
 * Joins line-level diffs separated by very short unchanged regions.
 * 
 * Algorithm from VSCode heuristicSequenceOptimizations.ts:
 * - Iterate up to 10 times until no more joins
 * - Join if: gap has ≤4 non-whitespace chars AND 
 *           (before diff is >5 lines total OR after diff is >5 lines total)
 * - Gap is measured in seq1 between lastResult.seq1_end and cur.seq1_start
 * 
 * VSCode:
 * ```typescript
 * const unchangedText = sequence1.getText(unchangedRange);
 * const unchangedTextWithoutWs = unchangedText.replace(/\s/g, '');
 * if (unchangedTextWithoutWs.length <= 4
 *     && (before.seq1Range.length + before.seq2Range.length > 5 
 *      || after.seq1Range.length + after.seq2Range.length > 5)) {
 *     return true;
 * }
 * ```
 */
SequenceDiffArray* remove_very_short_matching_lines_between_diffs(
    const ISequence* seq1,
    const ISequence* seq2 __attribute__((unused)),
    SequenceDiffArray* diffs) {
    
    if (!diffs || diffs->count == 0) {
        return diffs;
    }
    
    // Cast to LineSequence to access line text
    LineSequence* line_seq = (LineSequence*)seq1->data;
    
    int counter = 0;
    bool should_repeat;
    
    do {
        should_repeat = false;
        
        // Create result array
        SequenceDiff* result = malloc(sizeof(SequenceDiff) * diffs->capacity);
        int result_count = 0;
        
        // Start with first diff
        result[result_count++] = diffs->diffs[0];
        
        for (int i = 1; i < diffs->count; i++) {
            SequenceDiff cur = diffs->diffs[i];
            SequenceDiff* last_result = &result[result_count - 1];
            
            // Calculate unchanged range between last_result and cur
            int unchanged_start = last_result->seq1_end;
            int unchanged_end = cur.seq1_start;
            
            // Count non-whitespace characters in unchanged region
            int non_ws_count = 0;
            for (int idx = unchanged_start; idx < unchanged_end; idx++) {
                const char* line = line_seq->lines[idx];
                if (!line) continue;
                
                for (const char* p = line; *p; p++) {
                    if (*p != ' ' && *p != '\t' && *p != '\r' && *p != '\n') {
                        non_ws_count++;
                    }
                }
            }
            
            // Calculate diff sizes
            int before_total = (last_result->seq1_end - last_result->seq1_start) +
                              (last_result->seq2_end - last_result->seq2_start);
            int after_total = (cur.seq1_end - cur.seq1_start) +
                             (cur.seq2_end - cur.seq2_start);
            
            // VSCode logic: join if gap ≤4 non-ws chars AND one diff is large (>5 lines)
            bool should_join = (non_ws_count <= 4) && 
                              (before_total > 5 || after_total > 5);
            
            if (should_join) {
                should_repeat = true;
                // Join: extend last_result to include cur
                last_result->seq1_end = cur.seq1_end;
                last_result->seq2_end = cur.seq2_end;
            } else {
                result[result_count++] = cur;
            }
        }
        
        // Replace diffs with result
        free(diffs->diffs);
        diffs->diffs = result;
        diffs->count = result_count;
        
    } while (counter++ < 10 && should_repeat);
    
    return diffs;
}

// =============================================================================
// Legacy API - Backward Compatibility
// =============================================================================

/**
 * Legacy: optimize_sequence_diffs_legacy()
 * 
 * Wrapper for old API that uses raw line arrays.
 * Creates LineSequence wrappers and calls ISequence version.
 * 
 * @deprecated Use optimize_sequence_diffs() with ISequence
 */
bool optimize_sequence_diffs_legacy(SequenceDiffArray* diffs,
                                   const char** lines_a, int len_a,
                                   const char** lines_b, int len_b) {
    if (!diffs || !lines_a || !lines_b) {
        return false;
    }
    
    // Create LineSequence wrappers
    ISequence* seq1 = line_sequence_create(lines_a, len_a, false);
    ISequence* seq2 = line_sequence_create(lines_b, len_b, false);
    
    // Call ISequence version
    optimize_sequence_diffs(seq1, seq2, diffs);
    
    // Cleanup
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    
    return true;
}
