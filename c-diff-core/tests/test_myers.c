#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "../include/types.h"

// External functions to test
extern SequenceDiffArray* myers_diff_compute(const char** lines_a, int count_a, 
                                             const char** lines_b, int count_b);
extern void sequence_diff_array_free(SequenceDiffArray* arr);

// Test helper: print diff for debugging
static void print_diff(SequenceDiffArray* diffs) {
    printf("  Diffs count: %d\n", diffs->count);
    for (int i = 0; i < diffs->count; i++) {
        printf("    [%d] seq1[%d:%d] -> seq2[%d:%d]\n", 
               i,
               diffs->diffs[i].seq1_start, diffs->diffs[i].seq1_end,
               diffs->diffs[i].seq2_start, diffs->diffs[i].seq2_end);
    }
}

// Test 1: Empty vs empty
static void test_empty_vs_empty(void) {
    printf("Test 1: Empty vs empty...\n");
    
    const char** lines_a = NULL;
    const char** lines_b = NULL;
    
    SequenceDiffArray* diffs = myers_diff_compute(lines_a, 0, lines_b, 0);
    
    assert(diffs != NULL);
    assert(diffs->count == 0);
    
    sequence_diff_array_free(diffs);
    printf("  ✓ PASSED\n\n");
}

// Test 2: Identical files
static void test_identical_files(void) {
    printf("Test 2: Identical files...\n");
    
    const char* lines_a[] = { "line1", "line2", "line3" };
    const char* lines_b[] = { "line1", "line2", "line3" };
    
    SequenceDiffArray* diffs = myers_diff_compute(lines_a, 3, lines_b, 3);
    
    assert(diffs != NULL);
    assert(diffs->count == 0);
    
    sequence_diff_array_free(diffs);
    printf("  ✓ PASSED\n\n");
}

// Test 3: Single line insertion
static void test_single_line_insertion(void) {
    printf("Test 3: Single line insertion...\n");
    
    const char* lines_a[] = { "line1", "line3" };
    const char* lines_b[] = { "line1", "line2", "line3" };
    
    SequenceDiffArray* diffs = myers_diff_compute(lines_a, 2, lines_b, 3);
    
    print_diff(diffs);
    
    assert(diffs != NULL);
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 1);
    assert(diffs->diffs[0].seq1_end == 1);
    assert(diffs->diffs[0].seq2_start == 1);
    assert(diffs->diffs[0].seq2_end == 2);
    
    sequence_diff_array_free(diffs);
    printf("  ✓ PASSED\n\n");
}

// Test 4: Single line deletion
static void test_single_line_deletion(void) {
    printf("Test 4: Single line deletion...\n");
    
    const char* lines_a[] = { "line1", "line2", "line3" };
    const char* lines_b[] = { "line1", "line3" };
    
    SequenceDiffArray* diffs = myers_diff_compute(lines_a, 3, lines_b, 2);
    
    print_diff(diffs);
    
    assert(diffs != NULL);
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 1);
    assert(diffs->diffs[0].seq1_end == 2);
    assert(diffs->diffs[0].seq2_start == 1);
    assert(diffs->diffs[0].seq2_end == 1);
    
    sequence_diff_array_free(diffs);
    printf("  ✓ PASSED\n\n");
}

// Test 5: Single line modification (replacement)
static void test_single_line_modification(void) {
    printf("Test 5: Single line modification...\n");
    
    const char* lines_a[] = { "line1", "line2", "line3" };
    const char* lines_b[] = { "line1", "MODIFIED", "line3" };
    
    SequenceDiffArray* diffs = myers_diff_compute(lines_a, 3, lines_b, 3);
    
    print_diff(diffs);
    
    assert(diffs != NULL);
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 1);
    assert(diffs->diffs[0].seq1_end == 2);
    assert(diffs->diffs[0].seq2_start == 1);
    assert(diffs->diffs[0].seq2_end == 2);
    
    sequence_diff_array_free(diffs);
    printf("  ✓ PASSED\n\n");
}

// Test 6: Multiple changes
static void test_multiple_changes(void) {
    printf("Test 6: Multiple changes...\n");
    
    const char* lines_a[] = { "a", "b", "c", "d", "e" };
    const char* lines_b[] = { "a", "B", "c", "D", "e" };
    
    SequenceDiffArray* diffs = myers_diff_compute(lines_a, 5, lines_b, 5);
    
    print_diff(diffs);
    
    assert(diffs != NULL);
    assert(diffs->count == 2);
    
    // First change: b -> B
    assert(diffs->diffs[0].seq1_start == 1);
    assert(diffs->diffs[0].seq1_end == 2);
    assert(diffs->diffs[0].seq2_start == 1);
    assert(diffs->diffs[0].seq2_end == 2);
    
    // Second change: d -> D
    assert(diffs->diffs[1].seq1_start == 3);
    assert(diffs->diffs[1].seq1_end == 4);
    assert(diffs->diffs[1].seq2_start == 3);
    assert(diffs->diffs[1].seq2_end == 4);
    
    sequence_diff_array_free(diffs);
    printf("  ✓ PASSED\n\n");
}

// Test 7: Empty original (all insertions)
static void test_empty_original(void) {
    printf("Test 7: Empty original (all insertions)...\n");
    
    const char* lines_a[] = {};
    const char* lines_b[] = { "line1", "line2", "line3" };
    
    SequenceDiffArray* diffs = myers_diff_compute(lines_a, 0, lines_b, 3);
    
    print_diff(diffs);
    
    assert(diffs != NULL);
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 0);
    assert(diffs->diffs[0].seq1_end == 0);
    assert(diffs->diffs[0].seq2_start == 0);
    assert(diffs->diffs[0].seq2_end == 3);
    
    sequence_diff_array_free(diffs);
    printf("  ✓ PASSED\n\n");
}

// Test 8: Empty modified (all deletions)
static void test_empty_modified(void) {
    printf("Test 8: Empty modified (all deletions)...\n");
    
    const char* lines_a[] = { "line1", "line2", "line3" };
    const char* lines_b[] = {};
    
    SequenceDiffArray* diffs = myers_diff_compute(lines_a, 3, lines_b, 0);
    
    print_diff(diffs);
    
    assert(diffs != NULL);
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 0);
    assert(diffs->diffs[0].seq1_end == 3);
    assert(diffs->diffs[0].seq2_start == 0);
    assert(diffs->diffs[0].seq2_end == 0);
    
    sequence_diff_array_free(diffs);
    printf("  ✓ PASSED\n\n");
}

// Test 9: Complex diff scenario
static void test_complex_diff(void) {
    printf("Test 9: Complex diff scenario...\n");
    
    const char* lines_a[] = {
        "function foo() {",
        "  console.log('old');",
        "  return 1;",
        "}"
    };
    
    const char* lines_b[] = {
        "function foo() {",
        "  console.log('new');",
        "  const x = 42;",
        "  return x;",
        "}"
    };
    
    SequenceDiffArray* diffs = myers_diff_compute(lines_a, 4, lines_b, 5);
    
    print_diff(diffs);
    
    assert(diffs != NULL);
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 1);
    assert(diffs->diffs[0].seq1_end == 3);
    assert(diffs->diffs[0].seq2_start == 1);
    assert(diffs->diffs[0].seq2_end == 4);
    
    sequence_diff_array_free(diffs);
    printf("  ✓ PASSED\n\n");
}

int main(void) {
    printf("========================================\n");
    printf("Myers Diff Algorithm - Unit Tests\n");
    printf("========================================\n\n");
    
    test_empty_vs_empty();
    test_identical_files();
    test_single_line_insertion();
    test_single_line_deletion();
    test_single_line_modification();
    test_multiple_changes();
    test_empty_original();
    test_empty_modified();
    test_complex_diff();
    
    printf("========================================\n");
    printf("All tests passed! ✓\n");
    printf("========================================\n");
    
    return 0;
}
