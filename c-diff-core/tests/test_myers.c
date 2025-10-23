#include "../algorithms/myers.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

void print_diff_result(SequenceDiffArray* result) {
    printf("Found %d diffs:\n", result->count);
    for (int i = 0; i < result->count; i++) {
        printf("  Diff %d: seq1[%d,%d) -> seq2[%d,%d)\n",
               i,
               result->diffs[i].seq1_start,
               result->diffs[i].seq1_end,
               result->diffs[i].seq2_start,
               result->diffs[i].seq2_end);
    }
}

void test_identical_files() {
    printf("\n=== Test: Identical Files ===\n");
    const char* lines_a[] = {"line1", "line2", "line3"};
    const char* lines_b[] = {"line1", "line2", "line3"};
    
    SequenceDiffArray* result = myers_diff_algorithm(lines_a, 3, lines_b, 3);
    print_diff_result(result);
    assert(result->count == 0);
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

void test_empty_files() {
    printf("\n=== Test: Empty Files ===\n");
    const char** lines_a = NULL;
    const char** lines_b = NULL;
    
    SequenceDiffArray* result = myers_diff_algorithm(lines_a, 0, lines_b, 0);
    print_diff_result(result);
    assert(result->count == 0);
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

void test_one_line_change() {
    printf("\n=== Test: One Line Change ===\n");
    const char* lines_a[] = {"line1", "line2", "line3"};
    const char* lines_b[] = {"line1", "CHANGED", "line3"};
    
    SequenceDiffArray* result = myers_diff_algorithm(lines_a, 3, lines_b, 3);
    print_diff_result(result);
    assert(result->count == 1);
    assert(result->diffs[0].seq1_start == 1);
    assert(result->diffs[0].seq1_end == 2);
    assert(result->diffs[0].seq2_start == 1);
    assert(result->diffs[0].seq2_end == 2);
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

void test_insert_line() {
    printf("\n=== Test: Insert Line ===\n");
    const char* lines_a[] = {"line1", "line3"};
    const char* lines_b[] = {"line1", "line2", "line3"};
    
    SequenceDiffArray* result = myers_diff_algorithm(lines_a, 2, lines_b, 3);
    print_diff_result(result);
    assert(result->count == 1);
    assert(result->diffs[0].seq1_start == 1);
    assert(result->diffs[0].seq1_end == 1);  // Empty range in A
    assert(result->diffs[0].seq2_start == 1);
    assert(result->diffs[0].seq2_end == 2);  // One line in B
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

void test_delete_line() {
    printf("\n=== Test: Delete Line ===\n");
    const char* lines_a[] = {"line1", "line2", "line3"};
    const char* lines_b[] = {"line1", "line3"};
    
    SequenceDiffArray* result = myers_diff_algorithm(lines_a, 3, lines_b, 2);
    print_diff_result(result);
    assert(result->count == 1);
    assert(result->diffs[0].seq1_start == 1);
    assert(result->diffs[0].seq1_end == 2);  // One line in A
    assert(result->diffs[0].seq2_start == 1);
    assert(result->diffs[0].seq2_end == 1);  // Empty range in B
    printf("✓ PASSED\n");
    
    free(result->diffs);
    free(result);
}

void test_completely_different() {
    printf("\n=== Test: Completely Different ===\n");
    const char* lines_a[] = {"a", "b", "c"};
    const char* lines_b[] = {"x", "y", "z"};
    
    SequenceDiffArray* result = myers_diff_algorithm(lines_a, 3, lines_b, 3);
    print_diff_result(result);
    assert(result->count == 1);
    assert(result->diffs[0].seq1_start == 0);
    assert(result->diffs[0].seq1_end == 3);
    assert(result->diffs[0].seq2_start == 0);
    assert(result->diffs[0].seq2_end == 3);
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
    
    printf("\n==============================\n");
    printf("All tests passed! ✓\n");
    
    return 0;
}
