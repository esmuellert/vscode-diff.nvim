#define _POSIX_C_SOURCE 200809L
#include "diff_core.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>  // for isatty() and fileno()

// ============================================================================
// Version and Debug
// ============================================================================

const char* get_version(void) {
    return "0.1.0";
}

static const char* get_type_name(HighlightType type) {
    switch (type) {
        case HL_LINE_INSERT: return "INSERT";
        case HL_LINE_DELETE: return "DELETE";
        case HL_CHAR_INSERT: return "CHAR_INSERT";
        case HL_CHAR_DELETE: return "CHAR_DELETE";
        default: return "UNKNOWN";
    }
}

void diff_core_print_render_plan(const RenderPlan* plan) {
    // Use ANSI colors only if stdout is a TTY
    bool use_color = isatty(fileno(stdout));
    const char* cyan = use_color ? "\033[36m" : "";
    const char* yellow = use_color ? "\033[33m" : "";
    const char* green = use_color ? "\033[32m" : "";
    const char* red = use_color ? "\033[31m" : "";
    const char* bold = use_color ? "\033[1m" : "";
    const char* reset = use_color ? "\033[0m" : "";
    
    #define BOX_WIDTH 80
    
    printf("\n");
    printf("%s╔", bold);
    for (int i = 0; i < BOX_WIDTH - 2; i++) printf("═");
    printf("╗%s\n", reset);
    
    printf("%s║ %s[C-CORE] RENDER PLAN", bold, cyan);
    // Padding to align right border
    int title_len = strlen("[C-CORE] RENDER PLAN");
    for (int i = 0; i < BOX_WIDTH - title_len - 4; i++) printf(" ");
    printf("%s║%s\n", bold, reset);
    
    printf("%s╚", bold);
    for (int i = 0; i < BOX_WIDTH - 2; i++) printf("═");
    printf("╝%s\n", reset);
    printf("\n");
    
    // Left buffer
    char left_title[100];
    snprintf(left_title, sizeof(left_title), "LEFT BUFFER (%d lines)", plan->left.line_count);
    printf("%s┌─ %s ", yellow, left_title);
    int title_width = strlen(left_title) + 4;
    for (int i = 0; i < BOX_WIDTH - title_width - 2; i++) printf("─");
    printf("┐%s\n", reset);
    
    printf("%s│", yellow);
    for (int i = 0; i < BOX_WIDTH - 2; i++) printf(" ");
    printf("│%s\n", reset);
    
    for (int i = 0; i < plan->left.line_count; i++) {
        LineMetadata meta = plan->left.line_metadata[i];
        const char* type_name = get_type_name(meta.type);
        
        // Determine line color based on type
        const char* line_color = "";
        if (meta.type == HL_LINE_DELETE || meta.type == HL_CHAR_DELETE) {
            line_color = red;
        } else if (meta.type == HL_LINE_INSERT || meta.type == HL_CHAR_INSERT) {
            line_color = green;
        }
        
        char line_buf[200];
        snprintf(line_buf, sizeof(line_buf), 
                "  [%d] line_num=%-3d type=%-11s filler=%-3s char_hl=%d",
                i, meta.line_num, type_name,
                meta.is_filler ? "YES" : "NO",
                meta.char_highlight_count);
        
        printf("%s│%s%s", yellow, line_color, line_buf);
        int content_len = strlen(line_buf);
        for (int j = 0; j < BOX_WIDTH - content_len - 2; j++) printf(" ");
        printf("%s│%s\n", yellow, reset);
        
        // Character highlights
        for (int j = 0; j < meta.char_highlight_count; j++) {
            CharHighlight hl = meta.char_highlights[j];
            const char* hl_type = get_type_name(hl.type);
            
            char char_buf[200];
            snprintf(char_buf, sizeof(char_buf),
                    "      ↳ char[%d-%d] type=%s",
                    hl.start_col, hl.end_col, hl_type);
            
            printf("%s│%s%s", yellow, cyan, char_buf);
            // UTF-8 arrow ↳ is 3 bytes but displays as 1 char, so subtract 2 for visual width
            int char_len = strlen(char_buf) - 2;
            for (int k = 0; k < BOX_WIDTH - char_len - 2; k++) printf(" ");
            printf("%s│%s\n", yellow, reset);
        }
        
        if (i < plan->left.line_count - 1) {
            printf("%s│", yellow);
            for (int j = 0; j < BOX_WIDTH - 2; j++) printf(" ");
            printf("│%s\n", reset);
        }
    }
    
    printf("%s│", yellow);
    for (int i = 0; i < BOX_WIDTH - 2; i++) printf(" ");
    printf("│%s\n", reset);
    
    printf("%s└", yellow);
    for (int i = 0; i < BOX_WIDTH - 2; i++) printf("─");
    printf("┘%s\n", reset);
    printf("\n");
    
    // Right buffer
    char right_title[100];
    snprintf(right_title, sizeof(right_title), "RIGHT BUFFER (%d lines)", plan->right.line_count);
    printf("%s┌─ %s ", yellow, right_title);
    title_width = strlen(right_title) + 4;
    for (int i = 0; i < BOX_WIDTH - title_width - 2; i++) printf("─");
    printf("┐%s\n", reset);
    
    printf("%s│", yellow);
    for (int i = 0; i < BOX_WIDTH - 2; i++) printf(" ");
    printf("│%s\n", reset);
    
    for (int i = 0; i < plan->right.line_count; i++) {
        LineMetadata meta = plan->right.line_metadata[i];
        const char* type_name = get_type_name(meta.type);
        
        // Determine line color based on type
        const char* line_color = "";
        if (meta.type == HL_LINE_DELETE || meta.type == HL_CHAR_DELETE) {
            line_color = red;
        } else if (meta.type == HL_LINE_INSERT || meta.type == HL_CHAR_INSERT) {
            line_color = green;
        }
        
        char line_buf[200];
        snprintf(line_buf, sizeof(line_buf),
                "  [%d] line_num=%-3d type=%-11s filler=%-3s char_hl=%d",
                i, meta.line_num, type_name,
                meta.is_filler ? "YES" : "NO",
                meta.char_highlight_count);
        
        printf("%s│%s%s", yellow, line_color, line_buf);
        int content_len = strlen(line_buf);
        for (int j = 0; j < BOX_WIDTH - content_len - 2; j++) printf(" ");
        printf("%s│%s\n", yellow, reset);
        
        // Character highlights
        for (int j = 0; j < meta.char_highlight_count; j++) {
            CharHighlight hl = meta.char_highlights[j];
            const char* hl_type = get_type_name(hl.type);
            
            char char_buf[200];
            snprintf(char_buf, sizeof(char_buf),
                    "      ↳ char[%d-%d] type=%s",
                    hl.start_col, hl.end_col, hl_type);
            
            printf("%s│%s%s", yellow, cyan, char_buf);
            // UTF-8 arrow ↳ is 3 bytes but displays as 1 char, so subtract 2 for visual width
            int char_len = strlen(char_buf) - 2;
            for (int k = 0; k < BOX_WIDTH - char_len - 2; k++) printf(" ");
            printf("%s│%s\n", yellow, reset);
        }
        
        if (i < plan->right.line_count - 1) {
            printf("%s│", yellow);
            for (int j = 0; j < BOX_WIDTH - 2; j++) printf(" ");
            printf("│%s\n", reset);
        }
    }
    
    printf("%s│", yellow);
    for (int i = 0; i < BOX_WIDTH - 2; i++) printf(" ");
    printf("│%s\n", reset);
    
    printf("%s└", yellow);
    for (int i = 0; i < BOX_WIDTH - 2; i++) printf("─");
    printf("┘%s\n", reset);
    printf("\n");
    
    #undef BOX_WIDTH
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
 * Myers-like algorithm for character-level LCS.
 * Returns indices of changed characters in both strings.
 * Uses dynamic programming to find longest common subsequence.
 */
static void compute_lcs_indices(const char* str_a, const char* str_b,
                                 int** changed_a, int* changed_count_a,
                                 int** changed_b, int* changed_count_b) {
    int len_a = strlen(str_a);
    int len_b = strlen(str_b);
    
    // DP table: dp[i][j] = length of LCS of str_a[0..i-1] and str_b[0..j-1]
    int** dp = malloc(sizeof(int*) * (len_a + 1));
    for (int i = 0; i <= len_a; i++) {
        dp[i] = malloc(sizeof(int) * (len_b + 1));
        memset(dp[i], 0, sizeof(int) * (len_b + 1));
    }
    
    // Build DP table
    for (int i = 1; i <= len_a; i++) {
        for (int j = 1; j <= len_b; j++) {
            if (str_a[i - 1] == str_b[j - 1]) {
                dp[i][j] = dp[i - 1][j - 1] + 1;
            } else {
                dp[i][j] = (dp[i - 1][j] > dp[i][j - 1]) ? dp[i - 1][j] : dp[i][j - 1];
            }
        }
    }
    
    // Allocate worst-case space for changed indices
    *changed_a = malloc(sizeof(int) * (len_a + 1));
    *changed_b = malloc(sizeof(int) * (len_b + 1));
    *changed_count_a = 0;
    *changed_count_b = 0;
    
    // Backtrack to find changed characters
    int i = len_a, j = len_b;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && str_a[i - 1] == str_b[j - 1]) {
            // Characters match - not changed
            i--;
            j--;
        } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
            // Character in str_b is inserted
            (*changed_b)[(*changed_count_b)++] = j - 1;
            j--;
        } else if (i > 0) {
            // Character in str_a is deleted
            (*changed_a)[(*changed_count_a)++] = i - 1;
            i--;
        }
    }
    
    // Reverse to get ascending order
    for (int k = 0; k < *changed_count_a / 2; k++) {
        int tmp = (*changed_a)[k];
        (*changed_a)[k] = (*changed_a)[*changed_count_a - 1 - k];
        (*changed_a)[*changed_count_a - 1 - k] = tmp;
    }
    for (int k = 0; k < *changed_count_b / 2; k++) {
        int tmp = (*changed_b)[k];
        (*changed_b)[k] = (*changed_b)[*changed_count_b - 1 - k];
        (*changed_b)[*changed_count_b - 1 - k] = tmp;
    }
    
    // Free DP table
    for (int i = 0; i <= len_a; i++) {
        free(dp[i]);
    }
    free(dp);
}

/**
 * Convert individual changed character indices into character ranges.
 * Groups consecutive changed characters into single highlight ranges.
 */
static CharHighlight* indices_to_ranges(int* indices, int count, int line_num,
                                        HighlightType type, int* out_count) {
    if (count == 0) {
        *out_count = 0;
        return NULL;
    }
    
    CharHighlight* ranges = malloc(sizeof(CharHighlight) * count);
    *out_count = 0;
    
    int range_start = indices[0];
    int range_end = indices[0] + 1;
    
    for (int i = 1; i < count; i++) {
        if (indices[i] == range_end) {
            // Consecutive character - extend range
            range_end++;
        } else {
            // Gap - save current range and start new one
            ranges[(*out_count)++] = (CharHighlight){
                .line_num = line_num,
                .start_col = range_start + 1,    // 1-indexed
                .end_col = range_end + 1,        // exclusive, 1-indexed
                .type = type
            };
            range_start = indices[i];
            range_end = indices[i] + 1;
        }
    }
    
    // Save final range
    ranges[(*out_count)++] = (CharHighlight){
        .line_num = line_num,
        .start_col = range_start + 1,
        .end_col = range_end + 1,
        .type = type
    };
    
    return ranges;
}

/**
 * Find Longest Common Subsequence (LCS) at character level.
 * Computes character-level diff using LCS algorithm.
 */
static void compute_char_diff(const char* str_a, const char* str_b,
                              CharHighlight** highlights_a, int* count_a,
                              CharHighlight** highlights_b, int* count_b,
                              int line_num_a, int line_num_b) {
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
    
    // Compute character-level LCS
    int* changed_a = NULL;
    int* changed_b = NULL;
    int changed_count_a = 0;
    int changed_count_b = 0;
    
    compute_lcs_indices(str_a, str_b, &changed_a, &changed_count_a,
                        &changed_b, &changed_count_b);
    
    // Convert indices to ranges
    *highlights_a = indices_to_ranges(changed_a, changed_count_a, line_num_a,
                                      HL_CHAR_DELETE, count_a);
    *highlights_b = indices_to_ranges(changed_b, changed_count_b, line_num_b,
                                      HL_CHAR_INSERT, count_b);
    
    free(changed_a);
    free(changed_b);
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
 * Line-level diff using LCS for better alignment.
 * This finds the longest common subsequence of lines, then produces
 * operations based on that alignment.
 */
static DiffOp* compute_line_diff(const char** lines_a, int count_a,
                                 const char** lines_b, int count_b,
                                 int* op_count) {
    // Build LCS table for lines
    int** lcs = malloc(sizeof(int*) * (count_a + 1));
    for (int i = 0; i <= count_a; i++) {
        lcs[i] = calloc(count_b + 1, sizeof(int));
    }
    
    // Fill LCS table
    for (int i = 1; i <= count_a; i++) {
        for (int j = 1; j <= count_b; j++) {
            if (lines_equal(lines_a[i-1], lines_b[j-1])) {
                lcs[i][j] = lcs[i-1][j-1] + 1;
            } else {
                lcs[i][j] = lcs[i-1][j] > lcs[i][j-1] ? lcs[i-1][j] : lcs[i][j-1];
            }
        }
    }
    
    // Backtrack to build operations
    DiffOp* ops = malloc(sizeof(DiffOp) * (count_a + count_b + 2));
    *op_count = 0;
    
    int i = count_a, j = count_b;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && lines_equal(lines_a[i-1], lines_b[j-1])) {
            // Equal lines - group consecutive equals
            int equal_count = 0;
            while (i > 0 && j > 0 && lines_equal(lines_a[i-1], lines_b[j-1])) {
                equal_count++;
                i--;
                j--;
            }
            // Insert at beginning (we're going backwards)
            memmove(&ops[1], &ops[0], sizeof(DiffOp) * (*op_count));
            ops[0] = (DiffOp){
                .type = 0,  // EQUAL
                .orig_start = i,
                .orig_len = equal_count,
                .mod_start = j,
                .mod_len = equal_count
            };
            (*op_count)++;
        }
        else if (i > 0 && j > 0 && lcs[i][j] == lcs[i-1][j-1]) {
            // Lines don't match but LCS didn't increase - MODIFY
            memmove(&ops[1], &ops[0], sizeof(DiffOp) * (*op_count));
            ops[0] = (DiffOp){
                .type = 3,  // MODIFY
                .orig_start = i - 1,
                .orig_len = 1,
                .mod_start = j - 1,
                .mod_len = 1
            };
            (*op_count)++;
            i--;
            j--;
        }
        else if (j > 0 && (i == 0 || lcs[i][j] == lcs[i][j-1])) {
            // INSERT operation - group consecutive inserts
            int insert_count = 0;
            while (j > 0 && (i == 0 || lcs[i][j] == lcs[i][j-1])) {
                insert_count++;
                j--;
            }
            memmove(&ops[1], &ops[0], sizeof(DiffOp) * (*op_count));
            ops[0] = (DiffOp){
                .type = 2,  // INSERT
                .orig_start = i,
                .orig_len = 0,
                .mod_start = j,
                .mod_len = insert_count
            };
            (*op_count)++;
        }
        else {
            // DELETE operation - group consecutive deletes
            int delete_count = 0;
            while (i > 0 && (j == 0 || lcs[i][j] == lcs[i-1][j])) {
                delete_count++;
                i--;
            }
            memmove(&ops[1], &ops[0], sizeof(DiffOp) * (*op_count));
            ops[0] = (DiffOp){
                .type = 1,  // DELETE
                .orig_start = i,
                .orig_len = delete_count,
                .mod_start = j,
                .mod_len = 0
            };
            (*op_count)++;
        }
    }
    
    // Free LCS table
    for (int i = 0; i <= count_a; i++) {
        free(lcs[i]);
    }
    free(lcs);
    
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
