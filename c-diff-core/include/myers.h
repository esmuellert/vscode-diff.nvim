#ifndef MYERS_H
#define MYERS_H

#include "types.h"
#include "sequence.h"

/**
 * Equality scoring function for DP algorithm
 * Returns a score indicating how strongly two elements should be matched.
 * Higher scores prefer matching these elements.
 */
typedef double (*EqualityScoreFn)(const ISequence* seq1, const ISequence* seq2, 
                                   int offset1, int offset2, void* user_data);



/**
 * Myers O(MN) DP-based Diff Algorithm
 * 
 * Uses dynamic programming to compute LCS-based diff.
 * Suitable for small sequences where O(MN) space is acceptable.
 * 
 * @param seq1 First sequence
 * @param seq2 Second sequence
 * @param timeout_ms Maximum milliseconds to run (0 = no timeout)
 * @param hit_timeout Output: set to true if timeout was reached
 * @param score_fn Optional equality scoring function (NULL for default scoring)
 * @param user_data User data passed to score_fn
 * @return Array of SequenceDiff structures (caller must free)
 * 
 * VSCode Reference: dynamicProgrammingDiffing.ts
 */
SequenceDiffArray* myers_dp_diff_algorithm(const ISequence* seq1, const ISequence* seq2,
                                           int timeout_ms, bool* hit_timeout,
                                           EqualityScoreFn score_fn, void* user_data);

/**
 * Myers O(ND) Forward-only Algorithm (original implementation)
 * 
 * Direct implementation of Myers' O(ND) algorithm.
 * Used for large inputs.
 * 
 * @param seq1 First sequence
 * @param seq2 Second sequence
 * @param timeout_ms Maximum milliseconds to run (0 = no timeout)
 * @param hit_timeout Output: set to true if timeout was reached
 * @return Array of SequenceDiff structures (caller must free)
 */
SequenceDiffArray* myers_nd_diff_algorithm(const ISequence* seq1, const ISequence* seq2,
                                           int timeout_ms, bool* hit_timeout);

/**
 * Legacy wrapper for backward compatibility
 * 
 * Creates LineSequence wrappers and calls the ISequence version.
 * Used by existing tests until they're updated.
 * 
 * @deprecated Use compute_line_alignments() from line_level.h instead
 */
SequenceDiffArray* myers_diff_lines(const char** lines_a, int len_a,
                                    const char** lines_b, int len_b);

#endif // MYERS_H
