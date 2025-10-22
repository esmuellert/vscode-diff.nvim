#include "diff_core.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ============================================================================
// Version
// ============================================================================

const char* get_version(void) {
    return "0.1.0";
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Compare two lines for equality.
 */
static bool lines_equal(const char* a, const char* b) {
    if (a == NULL || b == NULL) {
        return a == b;
    }
    return strcmp(a, b) == 0;
}

/**
 * Find Longest Common Subsequence (LCS) at character level.
 * This is a simplified implementation for MVP.
 */
static void compute_char_diff(const char* str_a, const char* str_b,
                              CharHighlight** highlights_a, int* count_a,
                              CharHighlight** highlights_b, int* count_b,
                              int line_num_a, int line_num_b) {
    // For MVP: If strings differ, highlight entire lines
    *count_a = 0;
    *count_b = 0;
    *highlights_a = NULL;
    *highlights_b = NULL;
    
    if (str_a == NULL || str_b == NULL) {
        return;
    }
    
    if (strcmp(str_a, str_b) == 0) {
        return;  // No difference
    }
    
    // Simple heuristic: highlight entire line content
    int len_a = strlen(str_a);
    int len_b = strlen(str_b);
    
    if (len_a > 0) {
        *highlights_a = malloc(sizeof(CharHighlight));
        (*highlights_a)[0] = (CharHighlight){
            .line_num = line_num_a,
            .start_col = 1,
            .end_col = len_a + 1,  // exclusive
            .type = HL_CHAR_DELETE
        };
        *count_a = 1;
    }
    
    if (len_b > 0) {
        *highlights_b = malloc(sizeof(CharHighlight));
        (*highlights_b)[0] = (CharHighlight){
            .line_num = line_num_b,
            .start_col = 1,
            .end_col = len_b + 1,  // exclusive
            .type = HL_CHAR_INSERT
        };
        *count_b = 1;
    }
}

// ============================================================================
// Myers Diff Algorithm (Simplified for MVP)
// ============================================================================

typedef struct {
    int type;  // 0=equal, 1=delete, 2=insert, 3=modify
    int orig_start;
    int orig_len;
    int mod_start;
    int mod_len;
} DiffOp;

/**
 * Simplified diff algorithm for MVP.
 * This uses a basic line-by-line comparison.
 * For production, implement full Myers algorithm.
 */
static DiffOp* compute_line_diff(const char** lines_a, int count_a,
                                 const char** lines_b, int count_b,
                                 int* op_count) {
    // Allocate worst-case space
    DiffOp* ops = malloc(sizeof(DiffOp) * (count_a + count_b + 2));
    *op_count = 0;
    
    int i = 0, j = 0;
    
    while (i < count_a || j < count_b) {
        // Check if current lines are equal
        if (i < count_a && j < count_b && lines_equal(lines_a[i], lines_b[j])) {
            // Equal lines
            int start_i = i;
            int start_j = j;
            while (i < count_a && j < count_b && lines_equal(lines_a[i], lines_b[j])) {
                i++;
                j++;
            }
            ops[*op_count] = (DiffOp){
                .type = 0,
                .orig_start = start_i,
                .orig_len = i - start_i,
                .mod_start = start_j,
                .mod_len = j - start_j
            };
            (*op_count)++;
        }
        else if (i < count_a && j < count_b) {
            // Both have content but lines don't match - this is a modification
            ops[*op_count] = (DiffOp){
                .type = 3,  // modify
                .orig_start = i,
                .orig_len = 1,
                .mod_start = j,
                .mod_len = 1
            };
            (*op_count)++;
            
            i++;
            j++;
        }
        else if (i < count_a) {
            // Only original has content - delete
            int start_i = i;
            while (i < count_a && j >= count_b) {
                i++;
            }
            ops[*op_count] = (DiffOp){
                .type = 1,
                .orig_start = start_i,
                .orig_len = i - start_i,
                .mod_start = j,
                .mod_len = 0
            };
            (*op_count)++;
        }
        else {
            // Only modified has content - insert
            int start_j = j;
            while (j < count_b && i >= count_a) {
                j++;
            }
            ops[*op_count] = (DiffOp){
                .type = 2,
                .orig_start = i,
                .orig_len = 0,
                .mod_start = start_j,
                .mod_len = j - start_j
            };
            (*op_count)++;
        }
    }
    
    return ops;
}

// ============================================================================
// Render Plan Generation
// ============================================================================

RenderPlan* compute_diff(const char** lines_a, int count_a,
                         const char** lines_b, int count_b) {
    RenderPlan* plan = malloc(sizeof(RenderPlan));
    
    // Compute line-level diff
    int op_count;
    DiffOp* ops = compute_line_diff(lines_a, count_a, lines_b, count_b, &op_count);
    
    // Calculate total line count for each side (including filler lines)
    int max_lines = count_a > count_b ? count_a : count_b;
    
    // Allocate metadata arrays
    plan->left.line_metadata = malloc(sizeof(LineMetadata) * (max_lines + count_b + 1));
    plan->right.line_metadata = malloc(sizeof(LineMetadata) * (max_lines + count_a + 1));
    
    int left_idx = 0;
    int right_idx = 0;
    
    // Process diff operations
    for (int op_i = 0; op_i < op_count; op_i++) {
        DiffOp op = ops[op_i];
        
        if (op.type == 0) {
            // Equal lines - no highlighting
            for (int i = 0; i < op.orig_len; i++) {
                plan->left.line_metadata[left_idx++] = (LineMetadata){
                    .line_num = op.orig_start + i + 1,
                    .type = HL_LINE_INSERT,  // Dummy, not actually highlighted
                    .is_filler = false,
                    .char_highlight_count = 0,
                    .char_highlights = NULL
                };
                
                plan->right.line_metadata[right_idx++] = (LineMetadata){
                    .line_num = op.mod_start + i + 1,
                    .type = HL_LINE_INSERT,  // Dummy, not actually highlighted
                    .is_filler = false,
                    .char_highlight_count = 0,
                    .char_highlights = NULL
                };
            }
        }
        else if (op.type == 3) {
            // Modify operation - lines aligned with character-level diff
            for (int i = 0; i < op.orig_len; i++) {
                CharHighlight* char_hl_a = NULL;
                CharHighlight* char_hl_b = NULL;
                int char_count_a = 0;
                int char_count_b = 0;
                
                // Compute character-level diff between modified lines
                compute_char_diff(lines_a[op.orig_start + i], 
                                lines_b[op.mod_start + i],
                                &char_hl_a, &char_count_a,
                                &char_hl_b, &char_count_b,
                                op.orig_start + i + 1, 
                                op.mod_start + i + 1);
                
                plan->left.line_metadata[left_idx++] = (LineMetadata){
                    .line_num = op.orig_start + i + 1,
                    .type = HL_LINE_DELETE,
                    .is_filler = false,
                    .char_highlight_count = char_count_a,
                    .char_highlights = char_hl_a
                };
                
                plan->right.line_metadata[right_idx++] = (LineMetadata){
                    .line_num = op.mod_start + i + 1,
                    .type = HL_LINE_INSERT,
                    .is_filler = false,
                    .char_highlight_count = char_count_b,
                    .char_highlights = char_hl_b
                };
            }
        }
        else if (op.type == 1) {
            // Delete operation
            for (int i = 0; i < op.orig_len; i++) {
                CharHighlight* char_hl = NULL;
                int char_count = 0;
                
                // Compute character-level diff for deleted lines
                CharHighlight* dummy_b = NULL;
                int dummy_count_b = 0;
                compute_char_diff(lines_a[op.orig_start + i], "",
                                &char_hl, &char_count,
                                &dummy_b, &dummy_count_b,
                                op.orig_start + i + 1, 0);
                
                plan->left.line_metadata[left_idx++] = (LineMetadata){
                    .line_num = op.orig_start + i + 1,
                    .type = HL_LINE_DELETE,
                    .is_filler = false,
                    .char_highlight_count = char_count,
                    .char_highlights = char_hl
                };
                
                // Add filler line on right
                plan->right.line_metadata[right_idx++] = (LineMetadata){
                    .line_num = 0,  // Virtual line
                    .type = HL_LINE_INSERT,
                    .is_filler = true,
                    .char_highlight_count = 0,
                    .char_highlights = NULL
                };
            }
        }
        else if (op.type == 2) {
            // Insert operation
            for (int i = 0; i < op.mod_len; i++) {
                CharHighlight* char_hl = NULL;
                int char_count = 0;
                
                // Compute character-level diff for inserted lines
                CharHighlight* dummy_a = NULL;
                int dummy_count_a = 0;
                compute_char_diff("", lines_b[op.mod_start + i],
                                &dummy_a, &dummy_count_a,
                                &char_hl, &char_count,
                                0, op.mod_start + i + 1);
                
                // Add filler line on left
                plan->left.line_metadata[left_idx++] = (LineMetadata){
                    .line_num = 0,  // Virtual line
                    .type = HL_LINE_DELETE,
                    .is_filler = true,
                    .char_highlight_count = 0,
                    .char_highlights = NULL
                };
                
                plan->right.line_metadata[right_idx++] = (LineMetadata){
                    .line_num = op.mod_start + i + 1,
                    .type = HL_LINE_INSERT,
                    .is_filler = false,
                    .char_highlight_count = char_count,
                    .char_highlights = char_hl
                };
            }
        }
    }
    
    plan->left.line_count = left_idx;
    plan->right.line_count = right_idx;
    
    free(ops);
    
    return plan;
}

void free_render_plan(RenderPlan* plan) {
    if (!plan) return;
    
    // Free left side
    for (int i = 0; i < plan->left.line_count; i++) {
        free(plan->left.line_metadata[i].char_highlights);
    }
    free(plan->left.line_metadata);
    
    // Free right side
    for (int i = 0; i < plan->right.line_count; i++) {
        free(plan->right.line_metadata[i].char_highlights);
    }
    free(plan->right.line_metadata);
    
    free(plan);
}
