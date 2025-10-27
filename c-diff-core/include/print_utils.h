#ifndef PRINT_UTILS_H
#define PRINT_UTILS_H

#include "types.h"

/**
 * Print utilities for human-readable diff output.
 * Used across all tests for consistency.
 */

/**
 * Print a SequenceDiff in standard notation.
 * Format: seq1[start,end) -> seq2[start,end)
 * 
 * Example: seq1[1,5) -> seq2[1,5)
 * Means: Lines 1-4 in original differ from lines 1-4 in modified
 */
void print_sequence_diff(const SequenceDiff* diff, int index);

/**
 * Print an array of SequenceDiffs.
 * Shows count and details of each diff.
 */
void print_sequence_diff_array(const char* label, const SequenceDiffArray* diffs);

/**
 * Print a RangeMapping (character-level) in standard notation.
 * Format: L{line}:C{col}-L{line}:C{col} -> L{line}:C{col}-L{line}:C{col}
 * 
 * Example: L1:C7-L1:C12 -> L1:C7-L1:C15
 * Means: Line 1, columns 7-11 in original map to line 1, columns 7-14 in modified
 */
void print_range_mapping(const RangeMapping* mapping, int index);

/**
 * Print an array of RangeMappings.
 * Shows count and details of each character-level mapping.
 */
void print_range_mapping_array(const char* label, const RangeMappingArray* mappings);

/**
 * Print a DetailedLineRangeMapping in human-readable format.
 * Format: Lines {start}-{end} -> Lines {start}-{end} with {count} inner change(s)
 * 
 * Example:
 *   [0] Lines 1-2 -> Lines 1-2 (2 inner changes)
 *       Inner: L1:C1-L1:C4 -> L1:C1-L1:C4
 *       Inner: L2:C1-L2:C4 -> L2:C1-L2:C4
 */
void print_detailed_line_range_mapping(const DetailedLineRangeMapping* mapping, int index);

/**
 * Print an array of DetailedLineRangeMappings.
 * Shows count and details of each line-level mapping with inner changes.
 */
void print_detailed_line_range_mapping_array(const char* label, 
                                             const DetailedLineRangeMappingArray* mappings);

/**
 * Print a RenderPlan in human-readable format.
 * Shows metadata and highlights for both left and right sides.
 */
void diff_core_print_render_plan(const RenderPlan* plan);

#endif // PRINT_UTILS_H
