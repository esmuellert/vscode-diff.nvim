#include "types.h"
#include "myers.h"
#include "print_utils.h"
#include "test_utils.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

// ============================================================================
// Test Cases
// ============================================================================


void test_identical_files() {
    printf("\n=== Test: Identical Files ===\n");
    const char* lines_a[] = {"line1", "line2", "line3"};
    const char* lines_b[] = {"line1", "line2", "line3"};
    
    SequenceDiffArray* result = myers_diff_lines(lines_a, 3, lines_b, 3);
    print_sequence_diff_array("Result", result);
    assert(result->count == 0);
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

void test_empty_files() {
    printf("\n=== Test: Empty Files ===\n");
    const char** lines_a = NULL;
    const char** lines_b = NULL;
    
    SequenceDiffArray* result = myers_diff_lines(lines_a, 0, lines_b, 0);
    print_sequence_diff_array("Result", result);
    assert(result->count == 0);
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

void test_one_line_change() {
    printf("\n=== Test: One Line Change ===\n");
    const char* lines_a[] = {"line1", "line2", "line3"};
    const char* lines_b[] = {"line1", "CHANGED", "line3"};
    
    SequenceDiffArray* result = myers_diff_lines(lines_a, 3, lines_b, 3);
    print_sequence_diff_array("Result", result);
    
    assert_diff_count(result, 1);
    ASSERT_DIFF(result, 0, 1,2, 1,2);
    
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

void test_insert_line() {
    printf("\n=== Test: Insert Line ===\n");
    const char* lines_a[] = {"line1", "line3"};
    const char* lines_b[] = {"line1", "line2", "line3"};
    
    SequenceDiffArray* result = myers_diff_lines(lines_a, 2, lines_b, 3);
    print_sequence_diff_array("Result", result);
    
    assert_diff_count(result, 1);
    ASSERT_DIFF(result, 0, 1,1, 1,2);  // Empty range in A, one line in B
    
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

void test_delete_line() {
    printf("\n=== Test: Delete Line ===\n");
    const char* lines_a[] = {"line1", "line2", "line3"};
    const char* lines_b[] = {"line1", "line3"};
    
    SequenceDiffArray* result = myers_diff_lines(lines_a, 3, lines_b, 2);
    print_sequence_diff_array("Result", result);
    
    assert_diff_count(result, 1);
    ASSERT_DIFF(result, 0, 1,2, 1,1);  // One line in A, empty range in B
    
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

void test_completely_different() {
    printf("\n=== Test: Completely Different ===\n");
    const char* lines_a[] = {"a", "b", "c"};
    const char* lines_b[] = {"x", "y", "z"};
    
    SequenceDiffArray* result = myers_diff_lines(lines_a, 3, lines_b, 3);
    print_sequence_diff_array("Result", result);
    
    assert_diff_count(result, 1);
    ASSERT_DIFF(result, 0, 0,3, 0,3);
    
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

void test_multiple_separate_diffs() {
    printf("\n=== Test: Multiple Separate Diffs ===\n");
    const char* lines_a[] = {
        "line1",
        "OLD2",    // Will be changed
        "line3",
        "line4",
        "OLD5"     // Will be changed
    };
    const char* lines_b[] = {
        "line1",
        "NEW2",    // Changed
        "line3",
        "line4",
        "NEW5"     // Changed
    };
    
    SequenceDiffArray* result = myers_diff_lines(lines_a, 5, lines_b, 5);
    print_sequence_diff_array("Result", result);
    
    assert_diff_count(result, 2);
    ASSERT_DIFF(result, 0, 1,2, 1,2);  // First diff: line[1]
    ASSERT_DIFF(result, 1, 4,5, 4,5);  // Second diff: line[4]
    
    printf("✓ PASSED (validated all diff properties)\n");
    
    free(result->diffs);
    free(result);
}

void test_interleaved_changes() {
    printf("\n=== Test: Interleaved Changes (Insert, Delete, Modify) ===\n");
    const char* lines_a[] = {
        "keep1",
        "delete_me",
        "keep2",
        "modify_old"
    };
    const char* lines_b[] = {
        "keep1",
        "insert_new",
        "keep2",
        "modify_new"
    };
    
    SequenceDiffArray* result = myers_diff_lines(lines_a, 4, lines_b, 4);
    print_sequence_diff_array("Result", result);
    
    assert_diff_count(result, 2);
    ASSERT_DIFF(result, 0, 1,2, 1,2);  // line[1]: delete_me -> insert_new
    ASSERT_DIFF(result, 1, 3,4, 3,4);  // line[3]: modify_old -> modify_new
    
    printf("✓ PASSED (validated all diff properties)\n");
    
    free(result->diffs);
    free(result);
}

void test_snake_following() {
    printf("\n=== Test: Snake Following (Diagonal Matching) ===\n");
    const char* lines_a[] = {
        "same1",
        "same2",
        "same3",
        "different_a",
        "same4",
        "same5"
    };
    const char* lines_b[] = {
        "same1",
        "same2",
        "same3",
        "different_b",
        "same4",
        "same5"
    };
    
    SequenceDiffArray* result = myers_diff_lines(lines_a, 6, lines_b, 6);
    print_sequence_diff_array("Result", result);
    
    assert_diff_count(result, 1);
    ASSERT_DIFF(result, 0, 3,4, 3,4);  // Only line[3] differs
    
    printf("✓ PASSED (validated snake following: only middle line differs)\n");
    
    free(result->diffs);
    free(result);
}

void test_large_file() {
    printf("\n=== Test: Large File Performance (500 lines) ===\n");
    
    // Create large arrays
    const char** lines_a = malloc(sizeof(char*) * 500);
    const char** lines_b = malloc(sizeof(char*) * 500);
    
    // Most lines identical, with a few changes
    for (int i = 0; i < 500; i++) {
        char* buf_a = malloc(50);
        char* buf_b = malloc(50);
        
        if (i == 100 || i == 300) {
            // Make some lines different
            snprintf(buf_a, 50, "line_%d_OLD", i);
            snprintf(buf_b, 50, "line_%d_NEW", i);
        } else {
            // Most lines are identical
            snprintf(buf_a, 50, "line_%d", i);
            snprintf(buf_b, 50, "line_%d", i);
        }
        
        lines_a[i] = buf_a;
        lines_b[i] = buf_b;
    }
    
    SequenceDiffArray* result = myers_diff_lines(lines_a, 500, lines_b, 500);
    
    printf("  Large file: %d diff(s) found\n", result->count);
    print_sequence_diff_array("  Result", result);
    
    assert_diff_count(result, 2);
    ASSERT_DIFF(result, 0, 100,101, 100,101);  // First diff at line[100]
    ASSERT_DIFF(result, 1, 300,301, 300,301);  // Second diff at line[300]
    
    printf("✓ PASSED (validated all diff positions in large file)\n");
    
    // Cleanup
    for (int i = 0; i < 500; i++) {
        free((void*)lines_a[i]);
        free((void*)lines_b[i]);
    }
    free(lines_a);
    free(lines_b);
    free(result->diffs);
    free(result);
}

void test_worst_case() {
    printf("\n=== Test: Worst Case (Maximum Edit Distance) ===\n");
    
    // Every line different - worst case for Myers
    const char* lines_a[] = {
        "a1", "a2", "a3", "a4", "a5",
        "a6", "a7", "a8", "a9", "a10"
    };
    const char* lines_b[] = {
        "b1", "b2", "b3", "b4", "b5",
        "b6", "b7", "b8", "b9", "b10"
    };
    
    SequenceDiffArray* result = myers_diff_lines(lines_a, 10, lines_b, 10);
    print_sequence_diff_array("Result", result);
    
    assert_diff_count(result, 1);
    ASSERT_DIFF(result, 0, 0,10, 0,10);  // Entire range is one diff
    
    printf("✓ PASSED (validated worst case: entire range is one diff)\n");
    
    free(result->diffs);
    free(result);
}

void test_delete_and_add() {
    printf("\n=== Test: Delete Line and Add New Line ===\n");
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
    
    SequenceDiffArray* result = myers_diff_lines(original, 3, modified, 3);
    print_sequence_diff_array("Result", result);
    
    assert_diff_count(result, 2);
    ASSERT_DIFF(result, 0, 1,2, 1,1);  // Delete "line 2 to delete"
    ASSERT_DIFF(result, 1, 3,3, 2,3);  // Add "line 4 added"
    
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

int main() {
    printf("Running Myers Algorithm Tests\n");
    printf("==============================\n");
    
    test_empty_files();
    test_identical_files();
    test_one_line_change();
    test_insert_line();
    test_delete_line();
    test_completely_different();
    test_multiple_separate_diffs();
    test_interleaved_changes();
    test_snake_following();
    test_large_file();
    test_worst_case();
    test_delete_and_add();
    
    printf("\n==============================\n");
    printf("All tests passed! ✓\n");
    
    return 0;
}
