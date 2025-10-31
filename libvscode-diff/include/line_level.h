#ifndef LINE_LEVEL_H
#define LINE_LEVEL_H

#include "types.h"
#include "sequence.h"

/**
 * Line-Level Diff Computation (Steps 1-3 Consolidation) - FULL VSCODE PARITY
 * 
 * This module consolidates Steps 1-3 for line-level diff computation,
 * exactly mirroring VSCode's lineAlignmentResult calculation in defaultLinesDiffComputer.ts.
 * 
 * Pipeline (VSCode lines 66-87, 224-245):
 * 1. Create perfect hash map for line deduplication
 * 2. Create LineSequence with hashed lines
 * 3. Run Myers diff (DP for small files <1700 lines, O(ND) for large)
 *    - DP uses equality scoring for whitespace sensitivity
 * 4. optimizeSequenceDiffs() - Step 2 optimization
 * 5. removeVeryShortMatchingLinesBetweenDiffs() - Step 3 optimization
 * 
 * VSCode Reference:
 * src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts
 *   - computeDiff() lines 66-87, 224-245
 *   - Variable: lineAlignments (after Step 3)
 * 
 * REUSED BY: Step 4 (character-level refinement operates on line alignments)
 */

/**
 * Compute line-level diff alignments - VSCode Parity
 * 
 * This is the exact equivalent of VSCode's lineAlignmentResult computation
 * followed by optimizeSequenceDiffs and removeVeryShortMatchingLinesBetweenDiffs.
 * 
 * Algorithm (VSCode defaultLinesDiffComputer.ts:224-245):
 * 1. Create perfect hash map for line content
 * 2. Hash each line (trimmed) using perfect hash
 * 3. Create LineSequence(hashes, lines) for both sides
 * 4. If total lines < 1700:
 *      Use DP algorithm with equality scoring:
 *        score = (line1 == line2) ? (empty ? 0.1 : 1 + log(1 + len)) : 0.99
 *    Else:
 *      Use Myers O(ND) algorithm
 * 5. lineAlignments = optimizeSequenceDiffs(seq1, seq2, lineAlignments)
 * 6. lineAlignments = removeVeryShortMatchingLinesBetweenDiffs(seq1, seq2, lineAlignments)
 * 
 * @param lines_a Original file lines
 * @param len_a Number of lines in original
 * @param lines_b Modified file lines
 * @param len_b Number of lines in modified
 * @param timeout_ms Maximum milliseconds (0 = no timeout)
 * @param hit_timeout Output: set to true if timeout reached
 * @return SequenceDiffArray* Line alignments (caller must free with free_sequence_diff_array)
 * 
 * NOTE: This is the consolidation of Steps 1-3, producing the exact same output
 * as VSCode's lineAlignments variable at line 245.
 */
SequenceDiffArray* compute_line_alignments(
    const char** lines_a, int len_a,
    const char** lines_b, int len_b,
    int timeout_ms,
    bool* hit_timeout
);

/**
 * Helper: Free SequenceDiffArray
 */
void free_sequence_diff_array(SequenceDiffArray* arr);

#endif // LINE_LEVEL_H
