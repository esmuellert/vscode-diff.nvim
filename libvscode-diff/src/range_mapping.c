/**
 * Range Mapping Utilities - VSCode Parity
 * 
 * Converts character-level RangeMappings to line-level DetailedLineRangeMappings.
 * 
 * VSCode References:
 * - rangeMapping.ts: lineRangeMappingFromRangeMappings(), getLineRangeMapping()
 * - lineRange.ts: join(), intersectsOrTouches()
 */

#include "../include/range_mapping.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ============================================================================
// LineRange Helper Functions
// ============================================================================

/**
 * Join two line ranges (union).
 * 
 * Returns the smallest LineRange that contains both input ranges.
 * 
 * @param a First line range
 * @param b Second line range
 * @return Union of a and b
 * 
 * VSCode Reference: lineRange.ts join()
 * VSCode Parity: 100%
 */
LineRange line_range_join(LineRange a, LineRange b) {
    LineRange result;
    result.start_line = (a.start_line < b.start_line) ? a.start_line : b.start_line;
    result.end_line = (a.end_line > b.end_line) ? a.end_line : b.end_line;
    return result;
}

/**
 * Check if two line ranges intersect or touch.
 * 
 * Two ranges touch if one ends exactly where the other starts.
 * Two ranges intersect if they overlap.
 * 
 * @param a First line range
 * @param b Second line range
 * @return true if ranges intersect or are adjacent
 * 
 * VSCode Reference: lineRange.ts intersectsOrTouches()
 * VSCode Parity: 100%
 */
bool line_range_intersects_or_touches(LineRange a, LineRange b) {
    return a.start_line <= b.end_line 
        && b.start_line <= a.end_line;
}

/**
 * Get length of a line from lines array.
 * 
 * Helper function to get line length for boundary detection.
 * Line numbers are 1-based as in VSCode.
 * 
 * @param lines Array of line strings
 * @param line_count Total number of lines
 * @param line_number Line number (1-based)
 * @return Length of the line, or 0 if out of bounds
 */
static int get_line_length(const char** lines, int line_count, int line_number) {
    if (line_number < 1 || line_number > line_count) {
        return 0;
    }
    int index = line_number - 1;
    return (int)strlen(lines[index]);
}

// ============================================================================
// get_line_range_mapping - Single RangeMapping Conversion
// ============================================================================

/**
 * Convert single RangeMapping to DetailedLineRangeMapping.
 * 
 * Calculates appropriate line ranges based on character-level mapping,
 * applying deltas for line boundary handling:
 * - If change ends at column 1, exclude that line (lineEndDelta = -1)
 * - If change starts past line end, start from next line (lineStartDelta = 1)
 * 
 * @param range_mapping Character-level mapping to convert
 * @param original_lines Original file lines
 * @param original_line_count Number of original lines
 * @param modified_lines Modified file lines
 * @param modified_line_count Number of modified lines
 * @return DetailedLineRangeMapping with calculated line ranges and inner changes
 * 
 * VSCode Reference: rangeMapping.ts getLineRangeMapping()
 * VSCode Parity: 100%
 */
DetailedLineRangeMapping get_line_range_mapping(
    const RangeMapping* range_mapping,
    const char** original_lines,
    int original_line_count,
    const char** modified_lines,
    int modified_line_count
) {
    DetailedLineRangeMapping result;
    
    int line_start_delta = 0;
    int line_end_delta = 0;
    
    // If both ranges end at column 1, exclude the end line
    if (range_mapping->modified.end_col == 1 
        && range_mapping->original.end_col == 1
        && range_mapping->original.start_line + line_start_delta 
           <= range_mapping->original.end_line
        && range_mapping->modified.start_line + line_start_delta 
           <= range_mapping->modified.end_line) {
        line_end_delta = -1;
    }
    
    // If both ranges start past line end, start from next line
    if (range_mapping->modified.start_col - 1 
        >= get_line_length(modified_lines, modified_line_count, 
                          range_mapping->modified.start_line)
        && range_mapping->original.start_col - 1 
           >= get_line_length(original_lines, original_line_count,
                             range_mapping->original.start_line)
        && range_mapping->original.start_line 
           <= range_mapping->original.end_line + line_end_delta
        && range_mapping->modified.start_line 
           <= range_mapping->modified.end_line + line_end_delta) {
        line_start_delta = 1;
    }
    
    // Calculate line ranges with deltas
    result.original.start_line = range_mapping->original.start_line + line_start_delta;
    result.original.end_line = range_mapping->original.end_line + 1 + line_end_delta;
    
    result.modified.start_line = range_mapping->modified.start_line + line_start_delta;
    result.modified.end_line = range_mapping->modified.end_line + 1 + line_end_delta;
    
    // Preserve inner character change
    result.inner_changes = (RangeMapping*)malloc(sizeof(RangeMapping));
    if (result.inner_changes) {
        result.inner_changes[0] = *range_mapping;
        result.inner_change_count = 1;
    } else {
        result.inner_change_count = 0;
    }
    
    return result;
}

// ============================================================================
// Adjacent Grouping - Generic Implementation
// ============================================================================

/**
 * Group structure for holding grouped DetailedLineRangeMappings.
 */
typedef struct {
    DetailedLineRangeMapping* items;
    int count;
} Group;

/**
 * Dynamic array of groups.
 */
typedef struct {
    Group* groups;
    int count;
    int capacity;
} GroupArray;

/**
 * Predicate for grouping adjacent DetailedLineRangeMappings.
 * 
 * Two mappings should be grouped if their line ranges intersect or touch
 * on either the original or modified side.
 * 
 * @param a First mapping
 * @param b Second mapping
 * @return true if mappings should be grouped together
 * 
 * VSCode Reference: rangeMapping.ts lineRangeMappingFromRangeMappings() predicate
 */
static bool should_group_detailed_mappings(
    const DetailedLineRangeMapping* a,
    const DetailedLineRangeMapping* b
) {
    return line_range_intersects_or_touches(a->original, b->original)
        || line_range_intersects_or_touches(a->modified, b->modified);
}

/**
 * Group adjacent DetailedLineRangeMappings based on predicate.
 * 
 * Groups items if the predicate returns true for consecutive items.
 * Creates a new group when the predicate returns false.
 * 
 * @param items Array of DetailedLineRangeMappings to group
 * @param count Number of items
 * @return GroupArray containing grouped items, or NULL on allocation failure
 * 
 * VSCode Reference: arrays.ts groupAdjacentBy()
 * VSCode Parity: 100%
 */
static GroupArray* group_adjacent_detailed_mappings(
    DetailedLineRangeMapping* items,
    int count
) {
    GroupArray* result = (GroupArray*)malloc(sizeof(GroupArray));
    if (!result) return NULL;
    
    result->groups = (Group*)malloc(sizeof(Group) * 8);
    result->count = 0;
    result->capacity = 8;
    
    if (!result->groups) {
        free(result);
        return NULL;
    }
    
    Group* current_group = NULL;
    
    for (int i = 0; i < count; i++) {
        if (current_group && should_group_detailed_mappings(
            &current_group->items[current_group->count - 1], 
            &items[i]
        )) {
            // Add to current group
            current_group->items[current_group->count++] = items[i];
        } else {
            // Start new group
            if (result->count >= result->capacity) {
                result->capacity *= 2;
                Group* new_groups = (Group*)realloc(result->groups, 
                                                    sizeof(Group) * result->capacity);
                if (!new_groups) {
                    for (int j = 0; j < result->count; j++) {
                        free(result->groups[j].items);
                    }
                    free(result->groups);
                    free(result);
                    return NULL;
                }
                result->groups = new_groups;
            }
            
            current_group = &result->groups[result->count++];
            current_group->items = (DetailedLineRangeMapping*)malloc(
                sizeof(DetailedLineRangeMapping) * (count - i)
            );
            if (!current_group->items) {
                result->count--;
                break;
            }
            current_group->count = 0;
            current_group->items[current_group->count++] = items[i];
        }
    }
    
    return result;
}

// ============================================================================
// Main Conversion Function
// ============================================================================

/**
 * Convert character-level RangeMappings to line-level DetailedLineRangeMappings.
 * 
 * This is the main conversion function that:
 * 1. Converts each RangeMapping to DetailedLineRangeMapping via get_line_range_mapping()
 * 2. Groups adjacent mappings that touch or intersect
 * 3. Joins grouped mappings into single DetailedLineRangeMappings
 * 4. Collects all inner character changes
 * 
 * @param alignments Array of character-level mappings (from character diff)
 * @param original_lines Original file lines
 * @param original_line_count Number of original lines
 * @param modified_lines Modified file lines
 * @param modified_line_count Number of modified lines
 * @param dont_assert_start_line If true, skip start line assertions (not yet implemented)
 * @return Array of DetailedLineRangeMappings, caller must free with free_detailed_line_range_mapping_array()
 * 
 * VSCode Reference: rangeMapping.ts lineRangeMappingFromRangeMappings()
 * VSCode Parity: 100% (assertions not yet implemented)
 */
DetailedLineRangeMappingArray* line_range_mapping_from_range_mappings(
    const RangeMappingArray* alignments,
    const char** original_lines,
    int original_line_count,
    const char** modified_lines,
    int modified_line_count,
    bool dont_assert_start_line
) {
    (void)dont_assert_start_line;  // TODO: Add assertions
    
    if (!alignments || alignments->count == 0) {
        DetailedLineRangeMappingArray* result = 
            (DetailedLineRangeMappingArray*)malloc(sizeof(DetailedLineRangeMappingArray));
        if (result) {
            result->mappings = NULL;
            result->count = 0;
            result->capacity = 0;
        }
        return result;
    }
    
    // Step 1: Convert each RangeMapping to DetailedLineRangeMapping
    DetailedLineRangeMapping* mapped = (DetailedLineRangeMapping*)malloc(
        sizeof(DetailedLineRangeMapping) * alignments->count
    );
    if (!mapped) return NULL;
    
    for (int i = 0; i < alignments->count; i++) {
        mapped[i] = get_line_range_mapping(
            &alignments->mappings[i],
            original_lines, original_line_count,
            modified_lines, modified_line_count
        );
    }
    
    // Step 2: Group adjacent mappings
    GroupArray* groups = group_adjacent_detailed_mappings(mapped, alignments->count);
    if (!groups) {
        free(mapped);
        return NULL;
    }
    
    // Step 3: Create result array
    DetailedLineRangeMappingArray* result = 
        (DetailedLineRangeMappingArray*)malloc(sizeof(DetailedLineRangeMappingArray));
    if (!result) {
        for (int i = 0; i < groups->count; i++) {
            free(groups->groups[i].items);
        }
        free(groups->groups);
        free(groups);
        free(mapped);
        return NULL;
    }
    
    result->mappings = (DetailedLineRangeMapping*)malloc(
        sizeof(DetailedLineRangeMapping) * groups->count
    );
    result->count = 0;
    result->capacity = groups->count;
    
    if (!result->mappings) {
        free(result);
        for (int i = 0; i < groups->count; i++) {
            free(groups->groups[i].items);
        }
        free(groups->groups);
        free(groups);
        free(mapped);
        return NULL;
    }
    
    // Step 4: Join each group into a single DetailedLineRangeMapping
    for (int i = 0; i < groups->count; i++) {
        Group* g = &groups->groups[i];
        
        const DetailedLineRangeMapping* first = &g->items[0];
        const DetailedLineRangeMapping* last = &g->items[g->count - 1];
        
        DetailedLineRangeMapping change;
        
        // Join line ranges
        change.original = line_range_join(first->original, last->original);
        change.modified = line_range_join(first->modified, last->modified);
        
        // Collect all inner changes from group
        change.inner_changes = (RangeMapping*)malloc(sizeof(RangeMapping) * g->count);
        if (!change.inner_changes) {
            change.inner_change_count = 0;
        } else {
            change.inner_change_count = g->count;
            for (int j = 0; j < g->count; j++) {
                if (g->items[j].inner_change_count > 0 && g->items[j].inner_changes) {
                    change.inner_changes[j] = g->items[j].inner_changes[0];
                }
            }
        }
        
        result->mappings[result->count++] = change;
    }
    
    // Cleanup temporary structures
    for (int i = 0; i < groups->count; i++) {
        Group* g = &groups->groups[i];
        for (int j = 0; j < g->count; j++) {
            if (g->items[j].inner_changes) {
                free(g->items[j].inner_changes);
            }
        }
        free(g->items);
    }
    free(groups->groups);
    free(groups);
    free(mapped);
    
    return result;
}

/**
 * Free DetailedLineRangeMappingArray.
 * 
 * @param arr Array to free (can be NULL)
 */
void free_detailed_line_range_mapping_array(DetailedLineRangeMappingArray* arr) {
    if (!arr) return;
    
    if (arr->mappings) {
        for (int i = 0; i < arr->count; i++) {
            if (arr->mappings[i].inner_changes) {
                free(arr->mappings[i].inner_changes);
            }
        }
        free(arr->mappings);
    }
    free(arr);
}
