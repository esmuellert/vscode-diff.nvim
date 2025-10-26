// ============================================================================
// VSCode Advanced Diff Algorithm Implementation
// ============================================================================
// 
// ⚠️  IMPLEMENTATION STATUS: STUB (Day 1 - Phase 1)
//
// This file contains a TEMPORARY STUB implementation for Step 7 (render plan
// generation) to maintain Lua integration during development of Steps 1-6.
//
// Current behavior: Pass-through - copies original file content to both sides
// with no highlighting, no character diffs, and no alignment. This allows the
// plugin to load without errors while we build the real algorithm.
//
// Real implementation will be added after Steps 1-6 are complete and tested.
//
// ============================================================================

#include "../include/types.h"
#include "include/platform.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ============================================================================
// Version
// ============================================================================

const char* get_version(void) {
    return "0.2.0-stub";
}

// ============================================================================
// Step 7: Render Plan Generation (STUB)
// ============================================================================

/**
 * TEMPORARY STUB - Replace after Steps 1-6 are implemented.
 * 
 * This currently just passes through original text for Lua integration testing.
 * Real implementation will add:
 * - Highlighting based on DetailedLineRangeMapping
 * - Alignment (filler lines)
 * - Moved text indicators
 * 
 * Input:
 *   - lines_a/b: Original file content
 *   - count_a/b: Line counts
 * 
 * Output:
 *   - RenderPlan with both sides showing original content (no processing)
 */
RenderPlan* compute_diff(const char** lines_a, int count_a,
                         const char** lines_b, int count_b) {
    RenderPlan* plan = malloc(sizeof(RenderPlan));
    if (!plan) return NULL;
    
    // LEFT SIDE: Just copy original lines from lines_a
    plan->left.line_count = count_a;
    plan->left.line_metadata = malloc(sizeof(LineMetadata) * count_a);
    if (!plan->left.line_metadata) {
        free(plan);
        return NULL;
    }
    
    for (int i = 0; i < count_a; i++) {
        plan->left.line_metadata[i] = (LineMetadata){
            .line_num = i + 1,           // 1-indexed line number
            .type = HL_LINE_INSERT,      // Dummy type (not used in stub)
            .is_filler = false,          // No filler lines in stub
            .char_highlight_count = 0,   // No highlights in stub
            .char_highlights = NULL
        };
    }
    
    // RIGHT SIDE: Just copy original lines from lines_b
    plan->right.line_count = count_b;
    plan->right.line_metadata = malloc(sizeof(LineMetadata) * count_b);
    if (!plan->right.line_metadata) {
        free(plan->left.line_metadata);
        free(plan);
        return NULL;
    }
    
    for (int i = 0; i < count_b; i++) {
        plan->right.line_metadata[i] = (LineMetadata){
            .line_num = i + 1,           // 1-indexed line number
            .type = HL_LINE_INSERT,      // Dummy type (not used in stub)
            .is_filler = false,          // No filler lines in stub
            .char_highlight_count = 0,   // No highlights in stub
            .char_highlights = NULL
        };
    }
    
    return plan;
}

/**
 * Free all memory allocated in a RenderPlan.
 */
void free_render_plan(RenderPlan* plan) {
    if (!plan) return;
    
    // Free left side
    if (plan->left.line_metadata) {
        for (int i = 0; i < plan->left.line_count; i++) {
            free(plan->left.line_metadata[i].char_highlights);
        }
        free(plan->left.line_metadata);
    }
    
    // Free right side
    if (plan->right.line_metadata) {
        for (int i = 0; i < plan->right.line_count; i++) {
            free(plan->right.line_metadata[i].char_highlights);
        }
        free(plan->right.line_metadata);
    }
    
    free(plan);
}

// ============================================================================
// Debug Printing (Keep for testing)
// ============================================================================

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
    bool use_color = diff_isatty(diff_fileno(stdout));
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
