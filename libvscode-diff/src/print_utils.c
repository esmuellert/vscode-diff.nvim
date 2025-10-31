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

void diff_core_print_render_plan(const RenderPlan* plan) {
    if (!plan) {
        printf("RenderPlan: NULL\n");
        return;
    }
    
    printf("=== RenderPlan ===\n");
    
    // Left side
    printf("\nLeft side: %d lines\n", plan->left.line_count);
    for (int i = 0; i < plan->left.line_count; i++) {
        const LineMetadata* meta = &plan->left.line_metadata[i];
        const char* type_str = "UNKNOWN";
        if (meta->type == HL_LINE_INSERT) type_str = "INSERT";
        else if (meta->type == HL_LINE_DELETE) type_str = "DELETE";
        
        printf("  Line %d: type=%s", meta->line_num, type_str);
        
        if (meta->is_filler) {
            printf(" [FILLER]");
        }
        
        if (meta->char_highlight_count > 0) {
            printf(" (%d char highlights)", meta->char_highlight_count);
        }
        printf("\n");
        
        for (int j = 0; j < meta->char_highlight_count; j++) {
            const CharHighlight* ch = &meta->char_highlights[j];
            const char* ch_type_str = "UNKNOWN";
            if (ch->type == HL_CHAR_INSERT) ch_type_str = "INSERT";
            else if (ch->type == HL_CHAR_DELETE) ch_type_str = "DELETE";
            
            printf("    [%d] Line %d, cols %d-%d: %s\n", 
                   j, ch->line_num, ch->start_col, ch->end_col, ch_type_str);
        }
    }
    
    // Right side
    printf("\nRight side: %d lines\n", plan->right.line_count);
    for (int i = 0; i < plan->right.line_count; i++) {
        const LineMetadata* meta = &plan->right.line_metadata[i];
        const char* type_str = "UNKNOWN";
        if (meta->type == HL_LINE_INSERT) type_str = "INSERT";
        else if (meta->type == HL_LINE_DELETE) type_str = "DELETE";
        
        printf("  Line %d: type=%s", meta->line_num, type_str);
        
        if (meta->is_filler) {
            printf(" [FILLER]");
        }
        
        if (meta->char_highlight_count > 0) {
            printf(" (%d char highlights)", meta->char_highlight_count);
        }
        printf("\n");
        
        for (int j = 0; j < meta->char_highlight_count; j++) {
            const CharHighlight* ch = &meta->char_highlights[j];
            const char* ch_type_str = "UNKNOWN";
            if (ch->type == HL_CHAR_INSERT) ch_type_str = "INSERT";
            else if (ch->type == HL_CHAR_DELETE) ch_type_str = "DELETE";
            
            printf("    [%d] Line %d, cols %d-%d: %s\n", 
                   j, ch->line_num, ch->start_col, ch->end_col, ch_type_str);
        }
    }
    
    printf("\n");
}
