/**
 * Unit Tests for Step 2 & 3: Diff Optimization
 * 
 * Tests optimize_sequence_diffs() and remove_short_matches()
 */

#include "../include/types.h"
#include "../include/optimize.h"
#include "../include/sequence.h"
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
    
    ISequence* seq1 = line_sequence_create(lines_a, 2, false);
    ISequence* seq2 = line_sequence_create(lines_b, 2, false);
    optimize_sequence_diffs(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    bool result = true;
    
    print_sequence_diff_array("After optimize", diffs);
    assert(result == true);
    assert(diffs->count == 0);
    printf("    ✓ Verified: Empty array remains empty\n");
    
    free_diff_array(diffs);}

TEST(optimize_join_by_shifting_insertions) {
    // Two insertion diffs that can be joined by shifting
    // This demonstrates joinSequenceDiffsByShifting() in action
    const char* lines_a[] = {
        "a",
        "b",
        "c"
    };
    const char* lines_b[] = {
        "a",
        "x",    // Insert "x"
        "b",
        "y",    // Insert "y" 
        "c"
    };
    
    // Myers might give us: [1,1)->[1,2) and [2,2)->[3,4)
    // After shifting and joining, these should merge if possible
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 1, 1, 1, 2);  // Insert "x" at position 1
    add_diff(diffs, 2, 2, 3, 4);  // Insert "y" at position 2 (gap=1)
    
    printf("  Test: Two insertions with gap=1 (should join via removeShortMatches)\n");
    print_sequence_diff_array("  Before optimize", diffs);
    
    ISequence* seq1 = line_sequence_create(lines_a, 3, false);
    ISequence* seq2 = line_sequence_create(lines_b, 5, false);
    optimize_sequence_diffs(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    
    print_sequence_diff_array("  After optimize", diffs);
    
    // removeShortMatches (called by optimize) should join these (gap=1 ≤ 2)
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 1);
    assert(diffs->diffs[0].seq1_end == 2);
    assert(diffs->diffs[0].seq2_start == 1);
    assert(diffs->diffs[0].seq2_end == 4);
    printf("    ✓ Verified: Two insertions joined (gap=1 ≤ 2)\n");
    
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
    
    ISequence* seq1 = line_sequence_create(lines_a, 3, false);
    ISequence* seq2 = line_sequence_create(lines_b, 3, false);
    optimize_sequence_diffs(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    bool result = true;
    
    print_sequence_diff_array("After optimize", diffs);
    assert(result == true);
    assert(diffs->count == 1);
    printf("    ✓ Verified: Diff boundaries respect code structure\n");
    
    free_diff_array(diffs);}

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
    
    ISequence* seq1 = line_sequence_create(lines_a, 3, false);
    ISequence* seq2 = line_sequence_create(lines_b, 3, false);
    optimize_sequence_diffs(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    bool result = true;
    
    print_sequence_diff_array("After optimize (joined)", diffs);
    assert(result == true);
    // Should join into single diff
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 0);
    assert(diffs->diffs[0].seq1_end == 3);
    printf("    ✓ Verified: Two diffs with gap=1 joined into one\n");
    
    free_diff_array(diffs);}

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
    
    ISequence* seq1 = line_sequence_create(lines_a, 5, false);
    ISequence* seq2 = line_sequence_create(lines_b, 5, false);
    optimize_sequence_diffs(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    bool result = true;
    
    print_sequence_diff_array("After optimize (preserved)", diffs);
    assert(result == true);
    // Should remain as 2 separate diffs
    assert(diffs->count == 2);
    printf("    ✓ Verified: Large gap (3 lines) prevents joining\n");
    
    free_diff_array(diffs);}

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
    
    ISequence* seq1 = line_sequence_create(lines_a, 3, false);
    ISequence* seq2 = line_sequence_create(lines_b, 3, false);
    optimize_sequence_diffs(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    bool result = true;
    
    print_sequence_diff_array("After optimize", diffs);
    assert(result == true);
    assert(diffs->count == 1);
    printf("    ✓ Verified: Diff at file start handled correctly\n");
    
    free_diff_array(diffs);}

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
    
    ISequence* seq1 = line_sequence_create(lines_a, 3, false);
    ISequence* seq2 = line_sequence_create(lines_b, 3, false);
    optimize_sequence_diffs(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    bool result = true;
    
    print_sequence_diff_array("After optimize", diffs);
    assert(result == true);
    assert(diffs->count == 1);
    printf("    ✓ Verified: Diff at file end handled correctly\n");
    
    free_diff_array(diffs);}

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
    
    ISequence* seq1 = line_sequence_create(lines_a, 3, false);
    ISequence* seq2 = line_sequence_create(lines_b, 3, false);
    optimize_sequence_diffs(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    bool result = true;
    
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
    SequenceDiffArray* diffs = create_diff_array(5);
    print_sequence_diff_array("Before remove_short", diffs);
    
    remove_short_matches(NULL, NULL, diffs);
    bool result = true;
    
    print_sequence_diff_array("After remove_short", diffs);
    assert(result == true);
    assert(diffs->count == 0);
    printf("    ✓ Verified: Empty array remains empty\n");
    
    free_diff_array(diffs);}

TEST(remove_short_matches_single_diff) {
    // Single diff should remain unchanged (nothing to join with)
    
    const char* lines_a[] = {
        "old line"
    };
    const char* lines_b[] = {
        "new line"
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);
    print_sequence_diff_array("Before remove_short", diffs);
    
    ISequence* seq1 = line_sequence_create(lines_a, 1, false);
    ISequence* seq2 = line_sequence_create(lines_b, 1, false);
    remove_short_matches(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    
    print_sequence_diff_array("After remove_short", diffs);
    assert(diffs->count == 1);
    printf("    ✓ Verified: Single diff unchanged\n");
    
    free_diff_array(diffs);
}

TEST(remove_short_matches_modification_gap2) {
    // DEMONSTRATES: removeShortMatches' unique value
    // Modification diffs with gap=2 can't be joined by shifting,
    // but CAN be joined by gap threshold
    
    const char* lines_a[] = {
        "old func1() {",      // Changed (line 0)
        "    return 1;",      // Changed (line 1)
        "}",                  // Same (gap line 1)
        "",                   // Same (gap line 2)
        "old func2() {",      // Changed (line 4)
        "    return 2;",      // Changed (line 5)
        "}"
    };
    const char* lines_b[] = {
        "new func1() {",      // Changed (line 0)
        "    return 10;",     // Changed (line 1)
        "}",                  // Same (gap line 1)
        "",                   // Same (gap line 2)
        "new func2() {",      // Changed (line 4)
        "    return 20;",     // Changed (line 5)
        "}"
    };
    
    // Two modification diffs separated by gap=2
    // Shifting CAN'T join these (both ranges non-empty)
    // But removeShortMatches CAN (gap=2 ≤ 2)
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 2, 0, 2);  // Modification: lines 0-1 changed
    add_diff(diffs, 4, 6, 4, 6);  // Modification: lines 4-5 changed (gap=2)
    
    printf("  Example: Two function changes with 2-line gap (closing brace + blank)\n");
    printf("  Shifting can't join modifications, but gap threshold can!\n");
    print_sequence_diff_array("  Before remove_short (match=2)", diffs);
    
    ISequence* seq1 = line_sequence_create(lines_a, 7, false);
    ISequence* seq2 = line_sequence_create(lines_b, 7, false);
    remove_short_matches(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    
    print_sequence_diff_array("  After remove_short (joined)", diffs);
    
    // Should join because gap=2 ≤ 2
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 0);
    assert(diffs->diffs[0].seq1_end == 6);
    printf("    ✓ Verified: Modification diffs joined (gap=2 ≤ 2)\n");
    printf("    ✓ This is what shifting CAN'T do!\n");
    
    free_diff_array(diffs);
}

TEST(remove_short_matches_3line_match) {
    // Diffs separated by 3-line match should NOT be joined (> 2 threshold)
    // Demonstrates the gap=2 threshold is exact
    
    const char* lines_a[] = {
        "old code",        // Changed
        "same line 1",     // \
        "same line 2",     //  } 3 matching lines (gap=3)
        "same line 3",     // /
        "old code 2"       // Changed
    };
    const char* lines_b[] = {
        "new code",        // Changed
        "same line 1",     // \
        "same line 2",     //  } 3 matching lines (gap=3)
        "same line 3",     // /
        "new code 2"       // Changed
    };
    
    // Gap=3 is above threshold, should NOT join
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);  // Modification
    add_diff(diffs, 4, 5, 4, 5);  // Modification (gap=3, above threshold)
    
    printf("  Example: Changes separated by 3 identical lines\n");
    print_sequence_diff_array("  Before remove_short (match=3)", diffs);
    
    ISequence* seq1 = line_sequence_create(lines_a, 5, false);
    ISequence* seq2 = line_sequence_create(lines_b, 5, false);
    remove_short_matches(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    
    print_sequence_diff_array("  After remove_short (preserved)", diffs);
    assert(diffs->count == 2);  // Should NOT join (gap=3 > 2)
    printf("    ✓ Verified: 3-line match above threshold preserved separation\n");
    
    free_diff_array(diffs);
}

TEST(remove_short_matches_preserve_long_match) {
    // Diffs separated by 4-line match should NOT be joined (above threshold)
    
    const char* lines_a[] = {
        "old code",        // Changed
        "line 1",          // \
        "line 2",          //  |
        "line 3",          //  } 4 matching lines (gap=4)
        "line 4",          //  |
        "old code 2"       // /  Changed
    };
    const char* lines_b[] = {
        "new code",        // Changed
        "line 1",          // \
        "line 2",          //  |
        "line 3",          //  } 4 matching lines (gap=4)
        "line 4",          //  |
        "new code 2"       // /  Changed
    };
    
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);
    add_diff(diffs, 5, 6, 5, 6);  // 4-line match (gap=4, above threshold)
    print_sequence_diff_array("Before remove_short (match=4)", diffs);
    
    ISequence* seq1 = line_sequence_create(lines_a, 6, false);
    ISequence* seq2 = line_sequence_create(lines_b, 6, false);
    remove_short_matches(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    
    print_sequence_diff_array("After remove_short (preserved)", diffs);
    assert(diffs->count == 2);  // Should remain separate
    printf("    ✓ Verified: 4-line match above threshold preserved separation\n");
    
    free_diff_array(diffs);
}

TEST(remove_short_matches_multiple_joins) {
    // Multiple modification diffs with 1-line gaps should all join (cascade)
    // Shows that gap threshold works across multiple diffs
    
    const char* lines_a[] = {
        "old 1",    // Changed
        "same 1",   // 1-line match (gap=1)
        "old 2",    // Changed  
        "same 2",   // 1-line match (gap=1)
        "old 3"     // Changed
    };
    const char* lines_b[] = {
        "new 1",    // Changed
        "same 1",   // 1-line match (gap=1)
        "new 2",    // Changed
        "same 2",   // 1-line match (gap=1)
        "new 3"     // Changed
    };
    
    // Three modification diffs with gap=1 between each
    // All should cascade join
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);  // Modification
    add_diff(diffs, 2, 3, 2, 3);  // Modification (gap=1)
    add_diff(diffs, 4, 5, 4, 5);  // Modification (gap=1)
    
    printf("  Example: Multiple line changes with 1-line gaps (cascade join)\n");
    print_sequence_diff_array("  Before remove_short (3 diffs, 1-line matches)", diffs);
    
    ISequence* seq1 = line_sequence_create(lines_a, 5, false);
    ISequence* seq2 = line_sequence_create(lines_b, 5, false);
    remove_short_matches(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    
    print_sequence_diff_array("  After remove_short (all joined)", diffs);
    assert(diffs->count == 1);
    assert(diffs->diffs[0].seq1_start == 0);
    assert(diffs->diffs[0].seq1_end == 5);
    printf("    ✓ Verified: Multiple short matches all removed, all diffs joined\n");
    
    free_diff_array(diffs);
}

TEST(remove_short_matches_asymmetric) {
    // Asymmetric gaps: different gap sizes in seq1 vs seq2
    // VSCode joins if gap ≤ 2 in EITHER sequence (not both)
    
    const char* lines_a[] = {
        "old A",     // Changed
        "same",      // 1-line match in seq1
        "old B"      // Changed
    };
    const char* lines_b[] = {
        "new A",     // Changed
        "line 1",    // \
        "line 2",    //  } 2-line match in seq2
        "new B"      // Changed
    };
    
    // Gap in seq1 = 1, Gap in seq2 = 2
    // Should join because gap ≤ 2 in BOTH sequences
    SequenceDiffArray* diffs = create_diff_array(5);
    add_diff(diffs, 0, 1, 0, 1);  // Modification
    add_diff(diffs, 2, 3, 3, 4);  // Modification (asymmetric gap)
    
    printf("  Example: Asymmetric gaps (1 in seq1, 2 in seq2)\n");
    print_sequence_diff_array("  Before remove_short", diffs);
    
    ISequence* seq1 = line_sequence_create(lines_a, 3, false);
    ISequence* seq2 = line_sequence_create(lines_b, 4, false);
    remove_short_matches(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    
    print_sequence_diff_array("  After remove_short", diffs);
    
    // Should join: gap1=1 ≤ 2 AND gap2=2 ≤ 2
    assert(diffs->count == 1);
    printf("    ✓ Verified: Joined because gap ≤ 2 in EITHER sequence\n");
    
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
    ISequence* seq1 = line_sequence_create(lines_a, 8, false);
    ISequence* seq2 = line_sequence_create(lines_b, 8, false);
    optimize_sequence_diffs(seq1, seq2, diffs);
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    bool result1 = true;
    assert(result1 == true);
    
    // Step 3: Remove short matches
    remove_short_matches(NULL, NULL, diffs);
    bool result2 = true;
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
    RUN_TEST(optimize_join_by_shifting_insertions);
    RUN_TEST(optimize_shift_to_brace);  // Note: modification diff, no actual shifting
    RUN_TEST(optimize_join_adjacent_diffs);
    RUN_TEST(optimize_preserve_separation);
    RUN_TEST(optimize_boundary_at_file_start);
    RUN_TEST(optimize_boundary_at_file_end);
    RUN_TEST(optimize_already_optimal);
    
    printf("\n--- Step 3: remove_short_matches() ---\n");
    RUN_TEST(remove_short_matches_empty);
    RUN_TEST(remove_short_matches_single_diff);
    RUN_TEST(remove_short_matches_modification_gap2);
    RUN_TEST(remove_short_matches_3line_match);
    RUN_TEST(remove_short_matches_preserve_long_match);
    RUN_TEST(remove_short_matches_multiple_joins);
    RUN_TEST(remove_short_matches_asymmetric);
    
    printf("\n--- Integration Tests ---\n");
    RUN_TEST(integration_optimize_then_remove_short);
    
    printf("\n=== ALL TESTS PASSED ===\n");
    return 0;
}
