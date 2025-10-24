#include "../include/types.h"
#include "../include/myers.h"
#include "../include/print_utils.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

// ============================================================================
// Test Utility Functions
// ============================================================================

/**
 * Validate a single SequenceDiff has expected values
 * 
 * @param diff The diff to validate
 * @param expected_seq1_start Expected start in sequence 1
 * @param expected_seq1_end Expected end in sequence 1
 * @param expected_seq2_start Expected start in sequence 2
 * @param expected_seq2_end Expected end in sequence 2
 * @param diff_index Index of this diff (for error messages)
 */
static void assert_diff_equals(const SequenceDiff* diff,
                               int expected_seq1_start, int expected_seq1_end,
                               int expected_seq2_start, int expected_seq2_end,
                               int diff_index) {
    if (diff->seq1_start != expected_seq1_start) {
        printf("  ✗ FAIL: diff[%d].seq1_start = %d, expected %d\n", 
               diff_index, diff->seq1_start, expected_seq1_start);
        assert(0);
    }
    if (diff->seq1_end != expected_seq1_end) {
        printf("  ✗ FAIL: diff[%d].seq1_end = %d, expected %d\n",
               diff_index, diff->seq1_end, expected_seq1_end);
        assert(0);
    }
    if (diff->seq2_start != expected_seq2_start) {
        printf("  ✗ FAIL: diff[%d].seq2_start = %d, expected %d\n",
               diff_index, diff->seq2_start, expected_seq2_start);
        assert(0);
    }
    if (diff->seq2_end != expected_seq2_end) {
        printf("  ✗ FAIL: diff[%d].seq2_end = %d, expected %d\n",
               diff_index, diff->seq2_end, expected_seq2_end);
        assert(0);
    }
}

/**
 * Validate the entire diff array count
 * 
 * @param result The diff array to validate
 * @param expected_count Expected number of diffs
 */
static void assert_diff_count(const SequenceDiffArray* result, int expected_count) {
    if (result->count != expected_count) {
        printf("  ✗ FAIL: diff count = %d, expected %d\n",
               result->count, expected_count);
        assert(0);
    }
}

/**
 * Helper macro for validating a single diff in an array
 * Makes test code more readable
 * 
 * Usage: ASSERT_DIFF(result, 0, 1,2, 1,2);  // diff[0] = seq1[1,2) -> seq2[1,2)
 */
#define ASSERT_DIFF(result, index, s1_start, s1_end, s2_start, s2_end) \
    assert_diff_equals(&(result)->diffs[index], s1_start, s1_end, s2_start, s2_end, index)

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
    
    printf("\n==============================\n");
    printf("All tests passed! ✓\n");
    
    return 0;
}
