// Test render plan generation

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "diff_api.h"
#include "default_lines_diff_computer.h"
#include "render_plan.h"

// Helper to print render plan
void print_render_plan(RenderPlan* plan) {
    printf("=== LEFT (Original) ===\n");
    for (int i = 0; i < plan->left.line_count; i++) {
        LineMetadata* meta = &plan->left.line_metadata[i];
        printf("Line %d: ", meta->line_num);
        
        if (meta->type == HL_LINE_DELETE) {
            printf("DELETE");
        } else if (meta->type == HL_LINE_INSERT) {
            printf("INSERT");
        } else {
            printf("UNCHANGED");
        }
        
        if (meta->char_highlight_count > 0) {
            printf(" [%d char highlights]", meta->char_highlight_count);
        }
        printf("\n");
    }
    
    printf("\n=== RIGHT (Modified) ===\n");
    for (int i = 0; i < plan->right.line_count; i++) {
        LineMetadata* meta = &plan->right.line_metadata[i];
        printf("Line %d: ", meta->line_num);
        
        if (meta->type == HL_LINE_DELETE) {
            printf("DELETE");
        } else if (meta->type == HL_LINE_INSERT) {
            printf("INSERT");
        } else {
            printf("UNCHANGED");
        }
        
        if (meta->char_highlight_count > 0) {
            printf(" [%d char highlights]", meta->char_highlight_count);
        }
        printf("\n");
    }
}

// Test 1: Simple single line change
void test_simple_change() {
    printf("\n=== Test 1: Simple Single Line Change ===\n");
    
    const char* original[] = {
        "hello world",
        "unchanged line",
        "goodbye"
    };
    
    const char* modified[] = {
        "hello universe",
        "unchanged line",
        "goodbye"
    };
    
    DiffOptions opts = {
        .ignore_trim_whitespace = false,
        .max_computation_time_ms = 0,
        .compute_moves = false,
        .extend_to_subwords = true
    };
    
    RenderPlan* plan = compute_diff_render_plan(
        original, 3,
        modified, 3,
        &opts
    );
    
    assert(plan != NULL);
    assert(plan->left.line_count == 3);
    assert(plan->right.line_count == 3);
    
    // Line 1 should be marked as changed
    assert(plan->left.line_metadata[0].type == HL_LINE_DELETE);
    assert(plan->right.line_metadata[0].type == HL_LINE_INSERT);
    
    // Lines 2-3 should be unchanged
    // (Note: unchanged lines still have a type, but no char highlights)
    
    print_render_plan(plan);
    
    free_render_plan(plan);
    printf("✓ Test 1 passed\n");
}

// Test 2: Addition/deletion
void test_addition_deletion() {
    printf("\n=== Test 2: Addition and Deletion ===\n");
    
    const char* original[] = {
        "line 1",
        "line 2 to delete",
        "line 3"
    };
    
    const char* modified[] = {
        "line 1",
        "line 3",
        "line 4 added"
    };
    
    DiffOptions opts = {
        .ignore_trim_whitespace = false,
        .max_computation_time_ms = 0,
        .compute_moves = false,
        .extend_to_subwords = true
    };
    
    RenderPlan* plan = compute_diff_render_plan(
        original, 3,
        modified, 3,
        &opts
    );
    
    assert(plan != NULL);
    assert(plan->left.line_count == 3);
    assert(plan->right.line_count == 3);
    
    print_render_plan(plan);
    
    free_render_plan(plan);
    printf("✓ Test 2 passed\n");
}

// Test 3: Empty files
void test_empty() {
    printf("\n=== Test 3: Empty Files ===\n");
    
    const char* original[] = { "" };
    const char* modified[] = { "new content" };
    
    DiffOptions opts = {
        .ignore_trim_whitespace = false,
        .max_computation_time_ms = 0,
        .compute_moves = false,
        .extend_to_subwords = true
    };
    
    RenderPlan* plan = compute_diff_render_plan(
        original, 1,
        modified, 1,
        &opts
    );
    
    assert(plan != NULL);
    
    print_render_plan(plan);
    
    free_render_plan(plan);
    printf("✓ Test 3 passed\n");
}

int main() {
    printf("Testing Render Plan Generation\n");
    printf("================================\n");
    
    test_simple_change();
    test_addition_deletion();
    test_empty();
    
    printf("\n================================\n");
    printf("All tests passed!\n");
    
    return 0;
}
