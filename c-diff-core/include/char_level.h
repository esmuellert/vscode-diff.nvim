#ifndef CHAR_LEVEL_H
#define CHAR_LEVEL_H

#include "types.h"

/**
 * Step 4: Character-Level Refinement - FULL VSCODE PARITY
 * 
 * Implements VSCode's refineDiff() function with complete optimization pipeline:
 * 1. Create character sequences with line boundary tracking (LinesSliceCharSequence)
 * 2. Run Myers diff on characters
 * 3. optimizeSequenceDiffs() - Reuse Step 2 optimization
 * 4. extendDiffsToEntireWordIfAppropriate() - Word boundary extension
 * 5. extendDiffsToEntireWordIfAppropriate() for subwords (if enabled)
 * 6. removeShortMatches() - Remove ≤2 char gaps
 * 7. removeVeryShortMatchingTextBetweenLongDiffs() - Complex heuristic for long diffs
 * 8. Translate character offsets to (line, column) positions
 * 
 * VSCode Reference:
 * src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts - refineDiff()
 * src/vs/editor/common/diff/defaultLinesDiffComputer/linesSliceCharSequence.ts
 */

/**
 * Options for character-level refinement
 */
typedef struct {
    bool consider_whitespace_changes;  // If false, trim whitespace
    bool extend_to_subwords;           // If true, extend to CamelCase subwords
} CharLevelOptions;

/**
 * Refine a single line-level diff to character-level mappings - VSCode Parity
 * 
 * This is the main Step 4 function that implements VSCode's refineDiff().
 * 
 * VSCode returns: { mappings: RangeMapping[]; hitTimeout: boolean }
 * C equivalent: Returns mappings, sets out_hit_timeout flag
 * 
 * Algorithm (exact VSCode order):
 * 1. Create LinesSliceCharSequence for both sides
 * 2. Run Myers on character sequences (or DynamicProgramming if < 500 chars)
 * 3. optimizeSequenceDiffs(slice1, slice2, diffs)
 * 4. extendDiffsToEntireWordIfAppropriate(slice1, slice2, diffs, findWordContaining)
 * 5. if (options.extendToSubwords):
 *      extendDiffsToEntireWordIfAppropriate(slice1, slice2, diffs, findSubWordContaining, true)
 * 6. removeShortMatches(slice1, slice2, diffs)
 * 7. removeVeryShortMatchingTextBetweenLongDiffs(slice1, slice2, diffs)
 * 8. Translate character offsets to Range positions
 * 
 * @param line_diff Single line-level diff region to refine
 * @param lines_a Original file lines
 * @param len_a Number of lines in original
 * @param lines_b Modified file lines
 * @param len_b Number of lines in modified
 * @param options Refinement options
 * @param out_hit_timeout Output: Set to true if timeout occurred, can be NULL
 * @return RangeMappingArray* Character-level mappings (caller must free)
 */
RangeMappingArray* refine_diff_char_level(
    const SequenceDiff* line_diff,
    const char** lines_a, int len_a,
    const char** lines_b, int len_b,
    const CharLevelOptions* options,
    bool* out_hit_timeout
);

/**
 * Refine all line-level diffs to character-level - VSCode Parity
 * 
 * Calls refine_diff_char_level() for each line diff.
 * Also scans for whitespace-only changes between diffs if considerWhitespaceChanges.
 * 
 * VSCode behavior: Accumulates hitTimeout from all refineDiff() calls
 * C behavior: Sets out_hit_timeout if ANY refinement times out
 * 
 * @param line_diffs Line-level diffs from Steps 1-3
 * @param lines_a Original file lines
 * @param len_a Number of lines in original
 * @param lines_b Modified file lines
 * @param len_b Number of lines in modified
 * @param options Refinement options
 * @param out_hit_timeout Output: Set to true if any timeout occurred, can be NULL
 * @return RangeMappingArray* All character-level mappings (caller must free)
 */
RangeMappingArray* refine_all_diffs_char_level(
    const SequenceDiffArray* line_diffs,
    const char** lines_a, int len_a,
    const char** lines_b, int len_b,
    const CharLevelOptions* options,
    bool* out_hit_timeout
);

/**
 * Helper: Free RangeMappingArray
 */
void free_range_mapping_array(RangeMappingArray* arr);

#endif // CHAR_LEVEL_H
