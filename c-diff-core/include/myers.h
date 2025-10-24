#ifndef MYERS_H
#define MYERS_H

#include "types.h"
#include "sequence.h"

/**
 * Myers O(ND) Diff Algorithm
 * 
 * Computes shortest edit sequence between two sequences using Myers' algorithm.
 * Now works with ISequence abstraction for flexibility and optimization.
 * 
 * INFRASTRUCTURE REUSE:
 * - ISequence interface allows algorithm to work on any sequence type
 * - LineSequence: for line-level diffs (Step 1, Step 2-3)
 * - CharSequence: for character-level diffs (Step 4)
 * - Timeout support prevents hanging on large diffs
 * 
 * @param seq1 First sequence (implements ISequence)
 * @param seq2 Second sequence (implements ISequence)
 * @param timeout_ms Maximum milliseconds to run (0 = no timeout)
 * @param hit_timeout Output: set to true if timeout was reached
 * @return Array of SequenceDiff structures (caller must free)
 * 
 * VSCode Reference: src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/myersDiffAlgorithm.ts
 */
SequenceDiffArray* myers_diff_algorithm(const ISequence* seq1, const ISequence* seq2,
                                        int timeout_ms, bool* hit_timeout);

/**
 * Legacy wrapper for backward compatibility
 * 
 * Creates LineSequence wrappers and calls the ISequence version.
 * Used by existing tests until they're updated.
 * 
 * @deprecated Use myers_diff_algorithm() with ISequence instead
 */
SequenceDiffArray* myers_diff_lines(const char** lines_a, int len_a,
                                    const char** lines_b, int len_b);

#endif // MYERS_H
