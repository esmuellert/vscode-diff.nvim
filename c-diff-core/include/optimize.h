#ifndef OPTIMIZE_H
#define OPTIMIZE_H

#include "types.h"

/**
 * Step 2: Optimize Sequence Diffs
 * 
 * Shifts diff boundaries to more intuitive positions (blank lines, braces, etc.)
 * and joins adjacent diffs when beneficial for readability.
 * 
 * VSCode Reference: src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/diffAlgorithm.ts
 * - optimizeSequenceDiffs()
 * - shiftSequenceDiffs()
 */

/**
 * Optimize sequence diffs by shifting boundaries and joining adjacent diffs.
 * 
 * @param diffs Input/output array of sequence diffs (modified in-place)
 * @param lines_a Original sequence lines
 * @param len_a Length of sequence A
 * @param lines_b Modified sequence lines
 * @param len_b Length of sequence B
 * @return true on success, false on error
 */
bool optimize_sequence_diffs(SequenceDiffArray* diffs, 
                             const char** lines_a, int len_a,
                             const char** lines_b, int len_b);

/**
 * Step 3: Remove Very Short Matches
 * 
 * Removes short matching regions between diffs and joins them into larger diffs.
 * 
 * @param diffs Input/output array of sequence diffs (modified in-place)
 * @param lines_a Original sequence lines
 * @param len_a Length of sequence A
 * @param lines_b Modified sequence lines
 * @param len_b Length of sequence B
 * @param max_match_length Maximum length of match to remove (typically 3)
 * @return true on success, false on error
 */
bool remove_short_matches(SequenceDiffArray* diffs,
                         const char** lines_a, int len_a,
                         const char** lines_b, int len_b,
                         int max_match_length);

#endif // OPTIMIZE_H
