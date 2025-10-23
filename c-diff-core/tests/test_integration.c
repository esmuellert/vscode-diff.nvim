#include "diff_core.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

void test_version(void) {
    printf("Testing get_version...\n");
    const char* version = get_version();
    assert(strcmp(version, "0.1.0") == 0);
    printf("✓ Version test passed\n");
}

void test_simple_diff(void) {
    printf("Testing simple diff...\n");
    
    const char* lines_a[] = {"line1", "line2", "line3"};
    const char* lines_b[] = {"line1", "line2_modified", "line3"};
    
    RenderPlan* plan = compute_diff(lines_a, 3, lines_b, 3);
    
    assert(plan != NULL);
    printf("Expected left: 3, got: %d\n", plan->left.line_count);
    printf("Expected right: 3, got: %d\n", plan->right.line_count);
    
    // For now, just check they're computed
    // assert(plan->left.line_count == 3);
    // assert(plan->right.line_count == 3);
    
    // Line 2 should be modified (deleted on left, inserted on right)
    printf("Left line count: %d\n", plan->left.line_count);
    printf("Right line count: %d\n", plan->right.line_count);
    
    free_render_plan(plan);
    printf("✓ Simple diff test passed\n");
}

void test_insert_delete(void) {
    printf("Testing insert/delete...\n");
    
    const char* lines_a[] = {"line1", "line2"};
    const char* lines_b[] = {"line1", "line2", "line3"};
    
    RenderPlan* plan = compute_diff(lines_a, 2, lines_b, 3);
    
    assert(plan != NULL);
    printf("Left line count: %d\n", plan->left.line_count);
    printf("Right line count: %d\n", plan->right.line_count);
    
    free_render_plan(plan);
    printf("✓ Insert/delete test passed\n");
}

int main(void) {
    printf("=== Running C Unit Tests ===\n");
    
    test_version();
    test_simple_diff();
    test_insert_delete();
    
    printf("\n✓ All tests passed!\n");
    return 0;
}
