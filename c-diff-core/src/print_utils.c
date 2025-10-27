/**
 * Print utilities for human-readable diff output.
 * Provides consistent formatting across all tests.
 */

#include "../include/print_utils.h"
#include <stdio.h>

void print_sequence_diff(const SequenceDiff* diff, int index) {
    printf("    [%d] seq1[%d,%d) -> seq2[%d,%d)\n", index,
           diff->seq1_start, diff->seq1_end,
           diff->seq2_start, diff->seq2_end);
}

void print_sequence_diff_array(const char* label, const SequenceDiffArray* diffs) {
    if (!diffs) {
        printf("  %s: NULL\n", label);
        return;
    }
    
    printf("  %s: %d diff(s)\n", label, diffs->count);
    for (int i = 0; i < diffs->count; i++) {
        print_sequence_diff(&diffs->diffs[i], i);
    }
}

void print_range_mapping(const RangeMapping* mapping, int index) {
    printf("    [%d] L%d:C%d-L%d:C%d -> L%d:C%d-L%d:C%d\n", index,
           mapping->original.start_line, mapping->original.start_col,
           mapping->original.end_line, mapping->original.end_col,
           mapping->modified.start_line, mapping->modified.start_col,
           mapping->modified.end_line, mapping->modified.end_col);
}

void print_range_mapping_array(const char* label, const RangeMappingArray* mappings) {
    if (!mappings) {
        printf("  %s: NULL\n", label);
        return;
    }
    
    printf("  %s: %d character mapping(s)\n", label, mappings->count);
    for (int i = 0; i < mappings->count; i++) {
        print_range_mapping(&mappings->mappings[i], i);
    }
}

void print_detailed_line_range_mapping(const DetailedLineRangeMapping* mapping, int index) {
    if (!mapping) {
        printf("    [%d] NULL\n", index);
        return;
    }
    
    printf("    [%d] Lines %d-%d -> Lines %d-%d",
           index,
           mapping->original.start_line,
           mapping->original.end_line - 1,  // Show inclusive end
           mapping->modified.start_line,
           mapping->modified.end_line - 1);  // Show inclusive end
    
    if (mapping->inner_change_count > 0) {
        printf(" (%d inner change%s)\n", 
               mapping->inner_change_count,
               mapping->inner_change_count == 1 ? "" : "s");
        
        for (int i = 0; i < mapping->inner_change_count; i++) {
            printf("         Inner: L%d:C%d-L%d:C%d -> L%d:C%d-L%d:C%d\n",
                   mapping->inner_changes[i].original.start_line,
                   mapping->inner_changes[i].original.start_col,
                   mapping->inner_changes[i].original.end_line,
                   mapping->inner_changes[i].original.end_col,
                   mapping->inner_changes[i].modified.start_line,
                   mapping->inner_changes[i].modified.start_col,
                   mapping->inner_changes[i].modified.end_line,
                   mapping->inner_changes[i].modified.end_col);
        }
    } else {
        printf(" (no inner changes)\n");
    }
}

void print_detailed_line_range_mapping_array(const char* label, 
                                             const DetailedLineRangeMappingArray* mappings) {
    if (!mappings) {
        printf("  %s: NULL\n", label);
        return;
    }
    
    printf("  %s: %d line mapping(s)\n", label, mappings->count);
    for (int i = 0; i < mappings->count; i++) {
        print_detailed_line_range_mapping(&mappings->mappings[i], i);
    }
}
