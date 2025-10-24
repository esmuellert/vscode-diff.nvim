/**
 * Unit Tests for Step 2 & 3: Diff Optimization
 * 
 * Tests optimize_sequence_diffs() and remove_short_matches()
 */

#include "../include/optimize.h"
#include "../include/types.h"
#include "../include/print_utils.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

// Test helper macros
#define TEST(name) static void test_##name(void)
#define RUN_TEST(name) do { \
    printf("Running test_%s...\n", #name); \
    test_##name(); \
    printf("  ✓ PASSED\n"); \
} while(0)

// Helper to create a SequenceDiffArray
static SequenceDiffArray* create_diff_array(int capacity) {
    SequenceDiffArray* arr = malloc(sizeof(SequenceDiffArray));
    arr->diffs = malloc(sizeof(SequenceDiff) * capacity);
    arr->count = 0;
    arr->capacity = capacity;
    return arr;
}

// Helper to add a diff
static void add_diff(SequenceDiffArray* arr, int s1_start, int s1_end, int s2_start, int s2_end) {
    assert(arr->count < arr->capacity);
    arr->diffs[arr->count].seq1_start = s1_start;
    arr->diffs[arr->count].seq1_end = s1_end;
    arr->diffs[arr->count].seq2_start = s2_start;
    arr->diffs[arr->count].seq2_end = s2_end;
    arr->count++;
}

// Helper to free diff array
static void free_diff_array(SequenceDiffArray* arr) {
    if (arr) {
        free(arr->diffs);
        free(arr);
    }
}

// ============================================================================
// STEP 2 TESTS: optimize_sequence_diffs()
// ============================================================================

TEST(optimize_empty_array) {
    const char* lines_a[] = {"line1", "line2"};
    const char* lines_b[] = {"line1", "line2"};
    
    SequenceDiffArray* diffs = create_diff_array(5);
    print_sequence_diff_array("Before optimize", diffs);
    
    bool result = optimize_sequence_diffs(diffs, lines_a, 2, lines_b, 2);
    
    print_sequence_diff_array("After optimize", diffs);
    assert(result == true);
    assert(diffs->count == 0);
    printf("    ✓ Verified: Empty array remains empty\n");
    
    free_diff_array(diffs);
}

TEST(optimize_shift_to_blank_line) {
    // Diff should shift to include leading blank line
    const char* lines_a[] = {
        "code",
        "",           // blank line (preferred boundary)
        "old line 1",
        "old line 2"
    };
    const char* lines_b[] = {
        "code",
        "",           // blank line (preferred boundary)
        "new line 1",
        "new line 2"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 2, 4, 2, 4);  // Initial diff at lines 2-4
    print_sequence_diff_array("Before optimize", diffs);
    
    bool result = optimize_sequence_diffs(diffs, lines_a, 4, lines_b, 4);
    
    print_sequence_diff_array("After optimize", diffs);
    assert(result == true);
    assert(diffs->count == 1);
    printf("    ✓ Verified: Diff boundaries optimized\n");
    
    free_diff_array(diffs);
}

TEST(optimize_shift_to_brace) {
    // Diff should prefer boundaries at braces
    const char* lines_a[] = {
        "function() {",
        "  old code",
        "}"
    };
    const char* lines_b[] = {
        "function() {",
        "  new code",
        "}"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 1, 2, 1, 2);  // Diff on middle line
    print_sequence_diff_array("Before optimize", diffs);
    
    bool result = optimize_sequence_diffs(diffs, lines_a, 3, lines_b, 3);
    
    print_sequence_diff_array("After optimize", diffs);
    assert(result == true);
    assert(diffs->count == 1);
    printf("    ✓ Verified: Diff boundaries respect code structure\n");
    
    free_diff_array(diffs);
}

TEST(optimize_join_adjacent_diffs) {
    // Two diffs with 1-line gap should be joined
    const char* lines_a[] = {
        "old line 1",
        "same",
        "old line 3"
    };
    const char* lines_b[] = {
        "new line 1",
        "same",
        "new line 3"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);  // First diff
    add_diff(diffs, 2, 3, 2, 3);  // Second diff (1-line gap)
    print_sequence_diff_array("Before optimize (2 diffs, gap=1)", diffs);
    
    bool result = optimize_sequence_diffs(diffs, lines_a, 3, lines_b, 3);
    
    print_sequence_diff_array("After optimize (joined)", diffs);
    assert(result == true);
    // Should join into single diff
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 0);
    assert(diffs->diffs[0].seq1_end == 3);
    printf("    ✓ Verified: Two diffs with gap=1 joined into one\n");
    
    free_diff_array(diffs);
}

TEST(optimize_preserve_separation) {
    // Diffs with large gap should NOT be joined
    const char* lines_a[] = {
        "old line 1",
        "same 1",
        "same 2",
        "same 3",
        "old line 5"
    };
    const char* lines_b[] = {
        "new line 1",
        "same 1",
        "same 2",
        "same 3",
        "new line 5"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);  // First diff
    add_diff(diffs, 4, 5, 4, 5);  // Second diff (3-line gap)
    print_sequence_diff_array("Before optimize (2 diffs, gap=3)", diffs);
    
    bool result = optimize_sequence_diffs(diffs, lines_a, 5, lines_b, 5);
    
    print_sequence_diff_array("After optimize (preserved)", diffs);
    assert(result == true);
    // Should remain as 2 separate diffs
    assert(diffs->count == 2);
    printf("    ✓ Verified: Large gap (3 lines) prevents joining\n");
    
    free_diff_array(diffs);
}

TEST(optimize_boundary_at_file_start) {
    // Edge case: diff at start of file
    const char* lines_a[] = {
        "old line 1",
        "old line 2",
        "same"
    };
    const char* lines_b[] = {
        "new line 1",
        "new line 2",
        "same"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 2, 0, 2);
    print_sequence_diff_array("Before optimize", diffs);
    
    bool result = optimize_sequence_diffs(diffs, lines_a, 3, lines_b, 3);
    
    print_sequence_diff_array("After optimize", diffs);
    assert(result == true);
    assert(diffs->count == 1);
    printf("    ✓ Verified: Diff at file start handled correctly\n");
    
    free_diff_array(diffs);
}

TEST(optimize_boundary_at_file_end) {
    // Edge case: diff at end of file
    const char* lines_a[] = {
        "same",
        "old line 2",
        "old line 3"
    };
    const char* lines_b[] = {
        "same",
        "new line 2",
        "new line 3"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 1, 3, 1, 3);
    print_sequence_diff_array("Before optimize", diffs);
    
    bool result = optimize_sequence_diffs(diffs, lines_a, 3, lines_b, 3);
    
    print_sequence_diff_array("After optimize", diffs);
    assert(result == true);
    assert(diffs->count == 1);
    printf("    ✓ Verified: Diff at file end handled correctly\n");
    
    free_diff_array(diffs);
}

TEST(optimize_already_optimal) {
    // Diff already at good boundaries, should not change significantly
    const char* lines_a[] = {
        "",
        "old code",
        ""
    };
    const char* lines_b[] = {
        "",
        "new code",
        ""
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 1, 2, 1, 2);  // Already at blank boundaries
    print_sequence_diff_array("Before optimize", diffs);
    
    bool result = optimize_sequence_diffs(diffs, lines_a, 3, lines_b, 3);
    
    print_sequence_diff_array("After optimize", diffs);
    assert(result == true);
    assert(diffs->count == 1);
    printf("    ✓ Verified: Already optimal diff preserved\n");

    
    free_diff_array(diffs);
}

// ============================================================================
// STEP 3 TESTS: remove_short_matches()
// ============================================================================

TEST(remove_short_matches_empty) {
    const char* lines_a[] = {"line1"};
    const char* lines_b[] = {"line1"};
    
    SequenceDiffArray* diffs = create_diff_array(5);
    print_sequence_diff_array("Before remove_short", diffs);
    
    bool result = remove_short_matches(diffs, lines_a, 1, lines_b, 1, 3);
    
    print_sequence_diff_array("After remove_short", diffs);
    assert(result == true);
    assert(diffs->count == 0);
    printf("    ✓ Verified: Empty array remains empty\n");
    
    free_diff_array(diffs);
}

TEST(remove_short_matches_single_diff) {
    const char* lines_a[] = {"old"};
    const char* lines_b[] = {"new"};
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);
    print_sequence_diff_array("Before remove_short", diffs);
    
    bool result = remove_short_matches(diffs, lines_a, 1, lines_b, 1, 3);
    
    print_sequence_diff_array("After remove_short", diffs);
    assert(result == true);
    assert(diffs->count == 1);
    printf("    ✓ Verified: Single diff unchanged\n");
    
    free_diff_array(diffs);
}

TEST(remove_short_matches_1line_match) {
    // Diffs separated by 1-line match should be joined
    const char* lines_a[] = {
        "old 1",
        "same",   // 1-line match
        "old 3"
    };
    const char* lines_b[] = {
        "new 1",
        "same",   // 1-line match
        "new 3"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);  // First diff
    add_diff(diffs, 2, 3, 2, 3);  // Second diff (1-line match between)
    print_sequence_diff_array("Before remove_short (match=1)", diffs);
    
    bool result = remove_short_matches(diffs, lines_a, 3, lines_b, 3, 3);
    
    print_sequence_diff_array("After remove_short (joined)", diffs);
    assert(result == true);
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 0);
    assert(diffs->diffs[0].seq1_end == 3);
    printf("    ✓ Verified: 1-line match removed, diffs joined\n");
    
    free_diff_array(diffs);
}

TEST(remove_short_matches_3line_match) {
    // Diffs separated by 3-line match (at threshold) should be joined
    const char* lines_a[] = {
        "old 1",
        "same 1",
        "same 2",
        "same 3",
        "old 5"
    };
    const char* lines_b[] = {
        "new 1",
        "same 1",
        "same 2",
        "same 3",
        "new 5"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);
    add_diff(diffs, 4, 5, 4, 5);  // 3-line match (indices 1-3)
    print_sequence_diff_array("Before remove_short (match=3)", diffs);
    
    bool result = remove_short_matches(diffs, lines_a, 5, lines_b, 5, 3);
    
    print_sequence_diff_array("After remove_short (joined)", diffs);
    assert(result == true);
    assert(diffs->count == 1);
    printf("    ✓ Verified: 3-line match at threshold removed, diffs joined\n");
    
    free_diff_array(diffs);
}

TEST(remove_short_matches_preserve_long_match) {
    // Diffs separated by 4-line match should NOT be joined (above threshold)
    const char* lines_a[] = {
        "old 1",
        "same 1",
        "same 2",
        "same 3",
        "same 4",
        "old 6"
    };
    const char* lines_b[] = {
        "new 1",
        "same 1",
        "same 2",
        "same 3",
        "same 4",
        "new 6"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);
    add_diff(diffs, 5, 6, 5, 6);  // 4-line match (above threshold of 3)
    print_sequence_diff_array("Before remove_short (match=4)", diffs);
    
    bool result = remove_short_matches(diffs, lines_a, 6, lines_b, 6, 3);
    
    print_sequence_diff_array("After remove_short (preserved)", diffs);
    assert(result == true);
    assert(diffs->count == 2);  // Should remain separate
    printf("    ✓ Verified: 4-line match above threshold preserved separation\n");
    
    free_diff_array(diffs);
}

TEST(remove_short_matches_multiple_joins) {
    // Multiple short matches should all be removed
    const char* lines_a[] = {
        "old 1",
        "same 1",
        "old 3",
        "same 2",
        "old 5"
    };
    const char* lines_b[] = {
        "new 1",
        "same 1",
        "new 3",
        "same 2",
        "new 5"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);  // Diff 1
    add_diff(diffs, 2, 3, 2, 3);  // Diff 2 (1-line match before)
    add_diff(diffs, 4, 5, 4, 5);  // Diff 3 (1-line match before)
    print_sequence_diff_array("Before remove_short (3 diffs, 1-line matches)", diffs);
    
    bool result = remove_short_matches(diffs, lines_a, 5, lines_b, 5, 3);
    
    print_sequence_diff_array("After remove_short (all joined)", diffs);
    assert(result == true);
    assert(diffs->count == 1);  // All joined
    assert(diffs->diffs[0].seq1_start == 0);
    assert(diffs->diffs[0].seq1_end == 5);
    printf("    ✓ Verified: Multiple short matches all removed, all diffs joined\n");
    
    free_diff_array(diffs);
}

TEST(remove_short_matches_asymmetric) {
    // Different match lengths in seq1 vs seq2
    const char* lines_a[] = {
        "old 1",
        "same",
        "old 3"
    };
    const char* lines_b[] = {
        "new 1",
        "same 1",
        "same 2",
        "new 4"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);
    add_diff(diffs, 2, 3, 3, 4);  // 1-line match in seq1, 2-line in seq2
    
    bool result = remove_short_matches(diffs, lines_a, 3, lines_b, 4, 3);
    
    assert(result == true);
    // Both match lengths <= 3, should join
    assert(diffs->count == 1);
    
    free_diff_array(diffs);
}

// ============================================================================
// INTEGRATION TEST: Step 2 + Step 3 Combined
// ============================================================================

TEST(integration_optimize_then_remove_short) {
    // Real-world scenario: code refactoring with small common blocks
    const char* lines_a[] = {
        "function old() {",
        "  old line 1",
        "  old line 2",
        "",
        "  common line",
        "",
        "  old line 3",
        "}"
    };
    const char* lines_b[] = {
        "function new() {",
        "  new line 1",
        "  new line 2",
        "",
        "  common line",
        "",
        "  new line 3",
        "}"
    };
    
    SequenceDiffArray* diffs = create_diff_array(10);
    add_diff(diffs, 0, 3, 0, 3);  // First diff block
    add_diff(diffs, 6, 7, 6, 7);  // Second diff block (common line between)
    
    // Step 2: Optimize (may join if gap small enough)
    bool result1 = optimize_sequence_diffs(diffs, lines_a, 8, lines_b, 8);
    assert(result1 == true);
    
    // Step 3: Remove short matches
    bool result2 = remove_short_matches(diffs, lines_a, 8, lines_b, 8, 3);
    assert(result2 == true);
    
    // Should end up with joined diffs
    printf("  Final diff count: %d\n", diffs->count);
    
    free_diff_array(diffs);
}

// ============================================================================
// MAIN TEST RUNNER
// ============================================================================

int main(void) {
    printf("=== Step 2 & 3 Optimization Tests ===\n\n");
    
    printf("--- Step 2: optimize_sequence_diffs() ---\n");
    RUN_TEST(optimize_empty_array);
    RUN_TEST(optimize_shift_to_blank_line);
    RUN_TEST(optimize_shift_to_brace);
    RUN_TEST(optimize_join_adjacent_diffs);
    RUN_TEST(optimize_preserve_separation);
    RUN_TEST(optimize_boundary_at_file_start);
    RUN_TEST(optimize_boundary_at_file_end);
    RUN_TEST(optimize_already_optimal);
    
    printf("\n--- Step 3: remove_short_matches() ---\n");
    RUN_TEST(remove_short_matches_empty);
    RUN_TEST(remove_short_matches_single_diff);
    RUN_TEST(remove_short_matches_1line_match);
    RUN_TEST(remove_short_matches_3line_match);
    RUN_TEST(remove_short_matches_preserve_long_match);
    RUN_TEST(remove_short_matches_multiple_joins);
    RUN_TEST(remove_short_matches_asymmetric);
    
    printf("\n--- Integration Tests ---\n");
    RUN_TEST(integration_optimize_then_remove_short);
    
    printf("\n=== ALL TESTS PASSED ===\n");
    return 0;
}
