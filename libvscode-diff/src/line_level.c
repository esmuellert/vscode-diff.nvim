/**
 * Line-Level Diff Computation (Steps 1-3 Consolidation) - FULL VSCODE PARITY
 * 
 * Consolidates:
 * - Step 1: Myers diff algorithm with perfect hashing
 * - Step 2: optimizeSequenceDiffs (joinSequenceDiffsByShifting + shiftSequenceDiffs)
 * - Step 3: removeVeryShortMatchingLinesBetweenDiffs
 * 
 * This produces the exact equivalent of VSCode's lineAlignments variable
 * at defaultLinesDiffComputer.ts:245
 * 
 * VSCode Reference:
 * src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts
 */

#include "../include/line_level.h"
#include "../include/myers.h"
#include "../include/optimize.h"
#include "../include/sequence.h"
#include "../include/string_hash_map.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

/**
 * Equality scoring function for line-level DP algorithm
 * 
 * VSCode implementation (defaultLinesDiffComputer.ts:232-237):
 * ```typescript
 * (offset1, offset2) =>
 *   originalLines[offset1] === modifiedLines[offset2]
 *     ? modifiedLines[offset2].length === 0
 *       ? 0.1
 *       : 1 + Math.log(1 + modifiedLines[offset2].length)
 *     : 0.99
 * ```
 * 
 * This scoring function makes the DP algorithm prefer longer matching lines
 * and gives minimal score to empty line matches.
 */
typedef struct {
    const char** lines_a;
    const char** lines_b;
} LineEqualityContext;

static double line_equality_score(const ISequence* seq1, const ISequence* seq2,
                                  int offset1, int offset2, void* user_data) {
    (void)seq1;
    (void)seq2;
    
    LineEqualityContext* ctx = (LineEqualityContext*)user_data;
    const char* line_a = ctx->lines_a[offset1];
    const char* line_b = ctx->lines_b[offset2];
    
    if (strcmp(line_a, line_b) == 0) {
        // Lines are equal
        if (strlen(line_b) == 0) {
            return 0.1;  // Empty line match gets minimal score
        }
        return 1.0 + log(1.0 + (double)strlen(line_b));  // Prefer longer matches
    }
    
    return 0.99;  // Non-matching lines get nearly 1.0 (high penalty)
}

/**
 * compute_line_alignments() - VSCode Parity
 * 
 * Implements exact VSCode pipeline from defaultLinesDiffComputer.ts:224-245
 */
SequenceDiffArray* compute_line_alignments(
    const char** lines_a, int len_a,
    const char** lines_b, int len_b,
    int timeout_ms,
    bool* hit_timeout) {
    
    if (!lines_a || !lines_b || !hit_timeout) {
        return NULL;
    }
    
    *hit_timeout = false;
    
    // Step 1: Create perfect hash map (VSCode line 68-75)
    StringHashMap* hash_map = string_hash_map_create();
    
    // Step 2: Hash all lines (trimmed) - VSCode line 77-78
    // VSCode always uses l.trim() for hashing, regardless of ignoreTrimWhitespace option
    // The ignoreTrimWhitespace option only affects char-level comparison later
    
    // Step 3: Create LineSequence with trimmed hashes (VSCode line 80-81)
    // Pass true to hash trimmed lines, matching VSCode's getOrCreateHash(l.trim())
    ISequence* seq1 = line_sequence_create(lines_a, len_a, true, hash_map);
    ISequence* seq2 = line_sequence_create(lines_b, len_b, true, hash_map);
    
    // Step 4: Run Myers diff with algorithm selection (VSCode line 83-97)
    SequenceDiffArray* line_alignments;
    
    int total_lines = len_a + len_b;
    if (total_lines < 1700) {
        // Use DP algorithm with equality scoring for small files
        LineEqualityContext ctx = {
            .lines_a = lines_a,
            .lines_b = lines_b
        };
        
        line_alignments = myers_dp_diff_algorithm(
            seq1, seq2, timeout_ms, hit_timeout,
            line_equality_score, &ctx
        );
    } else {
        // Use Myers O(ND) for large files
        line_alignments = myers_nd_diff_algorithm(seq1, seq2, timeout_ms, hit_timeout);
    }
    
    if (!line_alignments) {
        seq1->destroy(seq1);
        seq2->destroy(seq2);
        string_hash_map_destroy(hash_map);
        return NULL;
    }
    
    // Step 5: Apply Step 2 optimization (VSCode line 244)
    line_alignments = optimize_sequence_diffs(seq1, seq2, line_alignments);
    
    // Step 6: Apply Step 3 optimization (VSCode line 245)
    line_alignments = remove_very_short_matching_lines_between_diffs(seq1, seq2, line_alignments);
    
    // Cleanup sequences (but keep the result)
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    string_hash_map_destroy(hash_map);
    
    return line_alignments;
}

/**
 * Helper: Free SequenceDiffArray
 */
void free_sequence_diff_array(SequenceDiffArray* arr) {
    if (arr) {
        free(arr->diffs);
        free(arr);
    }
}
