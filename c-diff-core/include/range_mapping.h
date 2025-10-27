#ifndef RANGE_MAPPING_H
#define RANGE_MAPPING_H

#include "types.h"
#include <stdbool.h>

/**
 * Range Mapping Utilities - VSCode Parity
 * 
 * This module provides functions to convert character-level RangeMappings
 * to line-level DetailedLineRangeMappings.
 * 
 * VSCode Reference:
 * src/vs/editor/common/diff/rangeMapping.ts
 */

// ============================================================================
// LineRange Helper Functions
// ============================================================================

/**
 * Join two line ranges (union).
 * 
 * VSCode: lineRange.ts line 169
 * TypeScript: join(other: LineRange): LineRange
 * 
 * Returns the smallest LineRange that contains both input ranges.
 */
LineRange line_range_join(LineRange a, LineRange b);

/**
 * Check if two line ranges intersect or touch.
 * 
 * VSCode: lineRange.ts line 184
 * TypeScript: intersectsOrTouches(other: LineRange): boolean
 * 
 * Returns true if ranges overlap or are adjacent.
 */
bool line_range_intersects_or_touches(LineRange a, LineRange b);

// ============================================================================
// Main Conversion Functions
// ============================================================================

/**
 * Convert a single RangeMapping to DetailedLineRangeMapping.
 * 
 * VSCode: rangeMapping.ts line 367 - getLineRangeMapping()
 * 
 * This function calculates the appropriate line ranges based on the
 * character-level mapping, applying deltas for line boundary handling.
 * 
 * @param range_mapping Character-level mapping
 * @param original_lines Original file lines
 * @param original_line_count Number of original lines
 * @param modified_lines Modified file lines
 * @param modified_line_count Number of modified lines
 * @return DetailedLineRangeMapping with calculated line ranges
 */
DetailedLineRangeMapping get_line_range_mapping(
    const RangeMapping* range_mapping,
    const char** original_lines,
    int original_line_count,
    const char** modified_lines,
    int modified_line_count
);

/**
 * Convert character-level RangeMappings to line-level DetailedLineRangeMappings.
 * 
 * VSCode: rangeMapping.ts line 322 - lineRangeMappingFromRangeMappings()
 * 
 * This is the main conversion function that:
 * 1. Converts each RangeMapping to DetailedLineRangeMapping
 * 2. Groups adjacent mappings
 * 3. Joins grouped mappings into single DetailedLineRangeMappings
 * 
 * @param alignments Array of character-level mappings
 * @param original_lines Original file lines
 * @param original_line_count Number of original lines
 * @param modified_lines Modified file lines
 * @param modified_line_count Number of modified lines
 * @param dont_assert_start_line If true, skip start line assertions
 * @return Array of DetailedLineRangeMappings (caller must free)
 */
DetailedLineRangeMappingArray* line_range_mapping_from_range_mappings(
    const RangeMappingArray* alignments,
    const char** original_lines,
    int original_line_count,
    const char** modified_lines,
    int modified_line_count,
    bool dont_assert_start_line
);

/**
 * Free DetailedLineRangeMappingArray.
 */
void free_detailed_line_range_mapping_array(DetailedLineRangeMappingArray* arr);

#endif // RANGE_MAPPING_H
