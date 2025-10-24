#ifndef OPTIMIZE_H
#define OPTIMIZE_H

#include "types.h"
#include "sequence.h"

/**
 * Steps 2-3: Sequence Diff Optimization - FULL VSCODE PARITY
 * 
 * Implements VSCode's heuristic sequence optimizations:
 * - joinSequenceDiffsByShifting() (called 2x)
 * - shiftSequenceDiffs() (boundary scoring)
 * - removeShortMatches() (join if gap ≤ 2)
 * 
 * REUSED BY: Step 4 (character-level optimization uses same functions)
 * 
 * VSCode Reference:
 * src/vs/editor/common/diff/defaultLinesDiffComputer/heuristicSequenceOptimizations.ts
 */

/**
 * Main optimization function - VSCode Parity
 * 
 * Applies all optimization heuristics:
 * 1. joinSequenceDiffsByShifting() - twice for better results
 * 2. shiftSequenceDiffs() - align at word/whitespace boundaries
 * 
 * @param seq1 First sequence (ISequence interface)
 * @param seq2 Second sequence (ISequence interface)
 * @param diffs Input/output array of diffs (modified in-place)
 * @return Optimized diff array (same pointer as input)
 * 
 * REUSED BY: Step 4 for character-level optimization
 */
SequenceDiffArray* optimize_sequence_diffs(const ISequence* seq1, const ISequence* seq2,
                                          SequenceDiffArray* diffs);

/**
 * Remove short matching regions between diffs - VSCode Parity
 * 
 * Joins diffs if gap ≤ 2 in EITHER sequence.
 * VSCode: "if (gap1 <= 2 || gap2 <= 2)"
 * 
 * @param seq1 First sequence (can be NULL, not used in current impl)
 * @param seq2 Second sequence (can be NULL, not used in current impl)
 * @param diffs Input/output array of diffs (modified in-place)
 * @return Modified diff array (same pointer as input)
 * 
 * REUSED BY: Step 4 for character-level short match removal
 */
SequenceDiffArray* remove_short_matches(const ISequence* seq1, const ISequence* seq2,
                                       SequenceDiffArray* diffs);

/**
 * Legacy wrapper for backward compatibility
 * 
 * Creates LineSequence wrappers and calls ISequence version.
 * 
 * @deprecated Use optimize_sequence_diffs() with ISequence instead
 */
bool optimize_sequence_diffs_legacy(SequenceDiffArray* diffs,
                                   const char** lines_a, int len_a,
                                   const char** lines_b, int len_b);

#endif // OPTIMIZE_H
