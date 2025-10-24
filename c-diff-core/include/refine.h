#ifndef REFINE_H
#define REFINE_H

#include "types.h"

/**
 * Step 4: Character-Level Refinement
 * 
 * For each line-level diff region, computes character-level differences
 * using Myers algorithm. Produces precise character ranges for inline highlighting.
 * 
 * VSCode Reference: 
 * src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts
 * - computeMovedLines() contains refinement logic
 * - Reuses MyersDiffAlgorithm.compute() for character sequences
 */

/**
 * Refine line-level diffs to character-level mappings.
 * 
 * For each SequenceDiff (line range), applies Myers diff at character level
 * to find precise changed regions within those lines.
 * 
 * @param line_diffs Line-level diffs from Steps 1-3
 * @param lines_a Original file lines
 * @param len_a Number of lines in original
 * @param lines_b Modified file lines
 * @param len_b Number of lines in modified
 * @return RangeMappingArray* Character-level mappings (caller must free)
 */
RangeMappingArray* refine_diffs_to_char_level(
    SequenceDiffArray* line_diffs,
    const char** lines_a, int len_a,
    const char** lines_b, int len_b
);

#endif // REFINE_H
