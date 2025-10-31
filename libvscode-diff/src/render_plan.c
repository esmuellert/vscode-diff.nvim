// ============================================================================
// Render Plan Generation
// ============================================================================
// 
// Converts LinesDiff (algorithmic output) to RenderPlan (UI structure).
// 
// Unlike VSCode which renders directly to Monaco editor, Neovim needs:
// 1. Line-level metadata for each buffer line
// 2. Character-level highlight regions within changed lines
// 3. Filler line tracking for alignment
//
// ============================================================================

#include "../include/render_plan.h"
#include <stdlib.h>
#include <string.h>

// ============================================================================
// Helper Structures
// ============================================================================

typedef struct {
    CharHighlight* highlights;
    int count;
    int capacity;
} CharHighlightBuilder;

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Initialize character highlight builder.
 */
static void init_char_highlight_builder(CharHighlightBuilder* builder) {
    builder->highlights = NULL;
    builder->count = 0;
    builder->capacity = 0;
}

/**
 * Add character highlight to builder.
 */
static void add_char_highlight(
    CharHighlightBuilder* builder,
    int line_num,
    int start_col,
    int end_col,
    HighlightType type
) {
    // Skip invalid ranges (but allow zero-length ranges for full-line highlights)
    if (start_col < 0 || end_col < 0 || start_col > end_col) {
        return;
    }
    
    // For empty ranges (start_col == end_col), this represents a zero-width
    // insertion point. We skip these as they don't need visual highlighting.
    if (start_col == end_col) {
        return;
    }
    
    if (builder->count >= builder->capacity) {
        size_t new_capacity = builder->capacity == 0 ? 4 : builder->capacity * 2;
        CharHighlight* new_highlights = (CharHighlight*)realloc(
            builder->highlights,
            new_capacity * sizeof(CharHighlight)
        );
        if (!new_highlights) return;
        builder->highlights = new_highlights;
        builder->capacity = new_capacity;
    }
    
    CharHighlight* hl = &builder->highlights[builder->count++];
    hl->line_num = line_num;
    hl->start_col = start_col;
    hl->end_col = end_col;
    hl->type = type;
}

/**
 * Create line metadata array for one side.
 */
static LineMetadata* create_line_metadata_array(int line_count) {
    LineMetadata* metadata = (LineMetadata*)calloc(line_count, sizeof(LineMetadata));
    if (!metadata) return NULL;
    
    // Initialize all lines as unchanged (no highlight)
    for (int i = 0; i < line_count; i++) {
        metadata[i].line_num = i + 1;
        metadata[i].type = HL_NONE;  // No highlight by default
        metadata[i].is_filler = false;
        metadata[i].char_highlight_count = 0;
        metadata[i].char_highlights = NULL;
    }
    
    return metadata;
}

// ============================================================================
// Main Function: generate_render_plan
// ============================================================================

/**
 * Generate render plan from LinesDiff.
 * 
 * Strategy:
 * 1. Create metadata arrays for both sides (all lines)
 * 2. For each DetailedLineRangeMapping:
 *    a. Mark affected lines with line-level highlights
 *    b. Add character-level highlights from inner_changes
 * 3. Fill in filler lines where needed for alignment
 * 
 * @param diff LinesDiff from compute_diff()
 * @param original_lines Original file lines
 * @param original_count Number of lines in original
 * @param modified_lines Modified file lines
 * @param modified_count Number of lines in modified
 * @return RenderPlan (caller must free)
 */
RenderPlan* generate_render_plan(
    const LinesDiff* diff,
    const char** original_lines,
    int original_count,
    const char** modified_lines,
    int modified_count
) {
    if (!diff) return NULL;
    
    RenderPlan* plan = (RenderPlan*)malloc(sizeof(RenderPlan));
    if (!plan) return NULL;
    
    // Allocate metadata for both sides
    plan->left.line_count = original_count;
    plan->left.line_metadata = create_line_metadata_array(original_count);
    
    plan->right.line_count = modified_count;
    plan->right.line_metadata = create_line_metadata_array(modified_count);
    
    if (!plan->left.line_metadata || !plan->right.line_metadata) {
        free_render_plan(plan);
        return NULL;
    }
    
    // Process each change mapping
    for (int i = 0; i < diff->changes.count; i++) {
        const DetailedLineRangeMapping* mapping = &diff->changes.mappings[i];
        
        // Get line ranges (1-indexed, end exclusive)
        int orig_start = mapping->original.start_line;
        int orig_end = mapping->original.end_line;
        int mod_start = mapping->modified.start_line;
        int mod_end = mapping->modified.end_line;
        
        // Mark line-level highlights
        // Original lines: DELETE
        for (int line = orig_start; line < orig_end; line++) {
            if (line >= 1 && line <= original_count) {
                plan->left.line_metadata[line - 1].type = HL_LINE_DELETE;
            }
        }
        
        // Modified lines: INSERT
        for (int line = mod_start; line < mod_end; line++) {
            if (line >= 1 && line <= modified_count) {
                plan->right.line_metadata[line - 1].type = HL_LINE_INSERT;
            }
        }
        
        // Process inner changes (character-level highlights)
        if (mapping->inner_changes && mapping->inner_change_count > 0) {
            // Build separate lists for each side
            CharHighlightBuilder orig_builder, mod_builder;
            init_char_highlight_builder(&orig_builder);
            init_char_highlight_builder(&mod_builder);
            
            for (int j = 0; j < mapping->inner_change_count; j++) {
                const RangeMapping* range = &mapping->inner_changes[j];
                
                // Original side: split multi-line ranges
                if (range->original.start_line == range->original.end_line) {
                    // Single line range
                    add_char_highlight(
                        &orig_builder,
                        range->original.start_line,
                        range->original.start_col,
                        range->original.end_col,
                        HL_CHAR_DELETE
                    );
                } else {
                    // Multi-line range: split into per-line highlights
                    // First line: from start_col to end of line
                    int first_line_idx = range->original.start_line - 1;
                    if (first_line_idx >= 0 && first_line_idx < original_count) {
                        int line_len = strlen(original_lines[first_line_idx]);
                        add_char_highlight(
                            &orig_builder,
                            range->original.start_line,
                            range->original.start_col,
                            line_len + 1,  // +1 for 1-based exclusive end
                            HL_CHAR_DELETE
                        );
                    }
                    
                    // Middle lines: full line highlights (if any)
                    for (int line = range->original.start_line + 1; line < range->original.end_line; line++) {
                        int line_idx = line - 1;
                        if (line_idx >= 0 && line_idx < original_count) {
                            int line_len = strlen(original_lines[line_idx]);
                            add_char_highlight(
                                &orig_builder,
                                line,
                                1,
                                line_len + 1,
                                HL_CHAR_DELETE
                            );
                        }
                    }
                    
                    // Last line: from start to end_col
                    if (range->original.end_col > 1) {
                        add_char_highlight(
                            &orig_builder,
                            range->original.end_line,
                            1,
                            range->original.end_col,
                            HL_CHAR_DELETE
                        );
                    }
                }
                
                // Modified side: split multi-line ranges
                if (range->modified.start_line == range->modified.end_line) {
                    // Single line range
                    add_char_highlight(
                        &mod_builder,
                        range->modified.start_line,
                        range->modified.start_col,
                        range->modified.end_col,
                        HL_CHAR_INSERT
                    );
                } else {
                    // Multi-line range: split into per-line highlights
                    // First line: from start_col to end of line
                    int first_line_idx = range->modified.start_line - 1;
                    if (first_line_idx >= 0 && first_line_idx < modified_count) {
                        int line_len = strlen(modified_lines[first_line_idx]);
                        add_char_highlight(
                            &mod_builder,
                            range->modified.start_line,
                            range->modified.start_col,
                            line_len + 1,
                            HL_CHAR_INSERT
                        );
                    }
                    
                    // Middle lines: full line highlights (if any)
                    for (int line = range->modified.start_line + 1; line < range->modified.end_line; line++) {
                        int line_idx = line - 1;
                        if (line_idx >= 0 && line_idx < modified_count) {
                            int line_len = strlen(modified_lines[line_idx]);
                            add_char_highlight(
                                &mod_builder,
                                line,
                                1,
                                line_len + 1,
                                HL_CHAR_INSERT
                            );
                        }
                    }
                    
                    // Last line: from start to end_col
                    if (range->modified.end_col > 1) {
                        add_char_highlight(
                            &mod_builder,
                            range->modified.end_line,
                            1,
                            range->modified.end_col,
                            HL_CHAR_INSERT
                        );
                    }
                }
            }
            
            // Attach character highlights to affected lines
            // Original side
            for (int j = 0; j < orig_builder.count; j++) {
                CharHighlight* hl = &orig_builder.highlights[j];
                int line_idx = hl->line_num - 1;
                
                if (line_idx >= 0 && line_idx < original_count) {
                    LineMetadata* meta = &plan->left.line_metadata[line_idx];
                    
                    // Grow array if needed
                    if (meta->char_highlight_count == 0) {
                        meta->char_highlights = (CharHighlight*)malloc(sizeof(CharHighlight));
                    } else {
                        CharHighlight* new_arr = (CharHighlight*)realloc(
                            meta->char_highlights,
                            (meta->char_highlight_count + 1) * sizeof(CharHighlight)
                        );
                        if (new_arr) {
                            meta->char_highlights = new_arr;
                        }
                    }
                    
                    if (meta->char_highlights) {
                        meta->char_highlights[meta->char_highlight_count++] = *hl;
                    }
                }
            }
            
            // Modified side
            for (int j = 0; j < mod_builder.count; j++) {
                CharHighlight* hl = &mod_builder.highlights[j];
                int line_idx = hl->line_num - 1;
                
                if (line_idx >= 0 && line_idx < modified_count) {
                    LineMetadata* meta = &plan->right.line_metadata[line_idx];
                    
                    // Grow array if needed
                    if (meta->char_highlight_count == 0) {
                        meta->char_highlights = (CharHighlight*)malloc(sizeof(CharHighlight));
                    } else {
                        CharHighlight* new_arr = (CharHighlight*)realloc(
                            meta->char_highlights,
                            (meta->char_highlight_count + 1) * sizeof(CharHighlight)
                        );
                        if (new_arr) {
                            meta->char_highlights = new_arr;
                        }
                    }
                    
                    if (meta->char_highlights) {
                        meta->char_highlights[meta->char_highlight_count++] = *hl;
                    }
                }
            }
            
            free(orig_builder.highlights);
            free(mod_builder.highlights);
        }
    }
    
    return plan;
}

/**
 * Free render plan.
 */
void free_render_plan(RenderPlan* plan) {
    if (!plan) return;
    
    // Free left side
    if (plan->left.line_metadata) {
        for (int i = 0; i < plan->left.line_count; i++) {
            if (plan->left.line_metadata[i].char_highlights) {
                free(plan->left.line_metadata[i].char_highlights);
            }
        }
        free(plan->left.line_metadata);
    }
    
    // Free right side
    if (plan->right.line_metadata) {
        for (int i = 0; i < plan->right.line_count; i++) {
            if (plan->right.line_metadata[i].char_highlights) {
                free(plan->right.line_metadata[i].char_highlights);
            }
        }
        free(plan->right.line_metadata);
    }
    
    free(plan);
}
