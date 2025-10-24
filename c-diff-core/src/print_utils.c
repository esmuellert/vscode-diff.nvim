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
