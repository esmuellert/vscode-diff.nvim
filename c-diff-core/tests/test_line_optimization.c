/**
 * Comprehensive Line-Level Optimization Tests (Steps 1+2+3)
 * 
 * TEST STRUCTURE (per specification):
 * 1. Setup: Define lines_a and lines_b
 * 2. After Step 1: Manually create Myers result + verify with actual Myers
 * 3. After Step 2: Manually calculate optimize result + verify
 * 4. After Step 3: Manually calculate removeVeryShort result + verify
 * 5. Cleanup
 * 
 * PIPELINE TESTED:
 * Myers → optimizeSequenceDiffs → removeVeryShortMatchingLinesBetweenDiffs
 * 
 * This tests the COMPLETE line-level optimization pipeline.
 * Character-level (Step 4) will be tested separately.
 */

#include "../include/types.h"
#include "../include/myers.h"
#include "../include/optimize.h"
#include "../include/sequence.h"
#include "../include/string_hash_map.h"
#include "../include/print_utils.h"
#include "test_utils.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ============================================================================
// TEST 1: Simple Addition (Single Line Insert)
// ============================================================================

TEST(line_opt_simple_addition) {
    printf("=== Test 1: Simple Addition ===\n");
    
    // 1. SETUP
    const char* lines_a[] = {"a", "b", "c"};
    const char* lines_b[] = {"a", "b", "INSERTED", "c"};
    
    // 2. AFTER STEP 1 (Myers)
    SequenceDiffArray* after_step1 = create_diff_array(10);
    add_diff(after_step1, 2, 2, 2, 3);  // Insert at position 2
    
    StringHashMap* hash_map = string_hash_map_create();
    ISequence* seq1 = line_sequence_create(lines_a, 3, false, hash_map);
    ISequence* seq2 = line_sequence_create(lines_b, 4, false, hash_map);
    bool timeout = false;
    SequenceDiffArray* myers = run_step1_myers(seq1, seq2, &timeout);
    print_sequence_diff_array("After Step 1 (Myers)", myers);
    printf("  Step 1 (Myers): ");
    assert_diffs_equal(myers, after_step1);
    printf("verified\n");
    
    // 3. AFTER STEP 2 (optimize)
    // No change expected (single insertion, nothing to optimize)
    SequenceDiffArray* after_step2 = create_diff_array(10);
    add_diff(after_step2, 2, 2, 2, 3);
    
    SequenceDiffArray* step2_actual = copy_diff_array(myers);
    optimize_sequence_diffs(seq1, seq2, step2_actual);
    print_sequence_diff_array("After Step 2 (optimize)", step2_actual);
    printf("  Step 2 (optimize): ");
    assert_diffs_equal(step2_actual, after_step2);
    printf("verified\n");
    
    // 4. AFTER STEP 3 (removeVeryShort)
    // No change expected (single diff, nothing to join)
    SequenceDiffArray* expected_final = create_diff_array(10);
    add_diff(expected_final, 2, 2, 2, 3);
    
    SequenceDiffArray* actual_final = copy_diff_array(step2_actual);
    remove_very_short_matching_lines_between_diffs(seq1, seq2, actual_final);
    print_sequence_diff_array("After Step 3 (removeVeryShort)", actual_final);
    printf("  Step 3 (removeVeryShort): ");
    assert_diffs_equal(actual_final, expected_final);
    printf("verified\n");
    
    printf("  ✓ Line optimization pipeline complete\n");
    
    // 5. CLEANUP
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    string_hash_map_destroy(hash_map);
    free_diff_array(myers);
    free_diff_array(after_step1);
    free_diff_array(step2_actual);
    free_diff_array(after_step2);
    free_diff_array(actual_final);
    free_diff_array(expected_final);
}

// ============================================================================
// TEST 2: Multiple Small Changes (Gap ≤4 non-ws chars)
// ============================================================================

TEST(line_opt_small_gap_join) {
    printf("=== Test 2: Small Gap But Small Diffs (Should NOT Join) ===\n");
    
    // 1. SETUP
    const char* lines_a[] = {"old1", "x", "old2"};
    const char* lines_b[] = {"new1", "x", "new2"};
    
    // 2. AFTER STEP 1 (Myers)
    SequenceDiffArray* after_step1 = create_diff_array(10);
    add_diff(after_step1, 0, 1, 0, 1);  // Modify line 0
    add_diff(after_step1, 2, 3, 2, 3);  // Modify line 2
    
    StringHashMap* hash_map = string_hash_map_create();
    ISequence* seq1 = line_sequence_create(lines_a, 3, false, hash_map);
    ISequence* seq2 = line_sequence_create(lines_b, 3, false, hash_map);
    bool timeout = false;
    SequenceDiffArray* myers = run_step1_myers(seq1, seq2, &timeout);
    print_sequence_diff_array("After Step 1 (Myers)", myers);
    printf("  Step 1 (Myers): ");
    assert_diffs_equal(myers, after_step1);
    printf("verified\n");
    
    // 3. AFTER STEP 2 (optimize)
    // No change (modifications are skipped by Step 2)
    SequenceDiffArray* after_step2 = create_diff_array(10);
    add_diff(after_step2, 0, 1, 0, 1);
    add_diff(after_step2, 2, 3, 2, 3);
    
    SequenceDiffArray* step2_actual = copy_diff_array(myers);
    optimize_sequence_diffs(seq1, seq2, step2_actual);
    print_sequence_diff_array("After Step 2 (optimize)", step2_actual);
    printf("  Step 2 (optimize): ");
    assert_diffs_equal(step2_actual, after_step2);
    printf("verified\n");
    
    // 4. AFTER STEP 3 (removeVeryShort)
    // NOT JOINED! Even though gap="x" has 1 char (≤4),
    // BOTH diffs are too small (1+1=2 ≤5)
    // VSCode requires: gap ≤4 AND (before >5 OR after >5)
    SequenceDiffArray* expected_final = create_diff_array(10);
    add_diff(expected_final, 0, 1, 0, 1);
    add_diff(expected_final, 2, 3, 2, 3);
    
    SequenceDiffArray* actual_final = copy_diff_array(step2_actual);
    remove_very_short_matching_lines_between_diffs(seq1, seq2, actual_final);
    print_sequence_diff_array("After Step 3 (removeVeryShort)", actual_final);
    printf("  Step 3 (removeVeryShort): ");
    assert_diffs_equal(actual_final, expected_final);
    printf("verified\n");
    
    printf("  ✓ Line optimization pipeline complete\n");
    printf("  ✓ Small diffs NOT joined (both ≤5 lines total)\n");
    
    // 5. CLEANUP
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    string_hash_map_destroy(hash_map);
    free_diff_array(myers);
    free_diff_array(after_step1);
    free_diff_array(step2_actual);
    free_diff_array(after_step2);
    free_diff_array(actual_final);
    free_diff_array(expected_final);
}

// ============================================================================
// TEST 3: Large Content Between Changes (Should NOT Join)
// ============================================================================

TEST(line_opt_large_gap_no_join) {
    printf("=== Test 3: Large Content Between Changes ===\n");
    
    // 1. SETUP
    const char* lines_a[] = {
        "old1",
        "line with substantial content here that exceeds limit",
        "old2"
    };
    const char* lines_b[] = {
        "new1",
        "line with substantial content here that exceeds limit",
        "new2"
    };
    
    // 2. AFTER STEP 1 (Myers)
    SequenceDiffArray* after_step1 = create_diff_array(10);
    add_diff(after_step1, 0, 1, 0, 1);
    add_diff(after_step1, 2, 3, 2, 3);
    
    StringHashMap* hash_map = string_hash_map_create();
    ISequence* seq1 = line_sequence_create(lines_a, 3, false, hash_map);
    ISequence* seq2 = line_sequence_create(lines_b, 3, false, hash_map);
    bool timeout = false;
    SequenceDiffArray* myers = run_step1_myers(seq1, seq2, &timeout);
    print_sequence_diff_array("After Step 1 (Myers)", myers);
    printf("  Step 1 (Myers): ");
    assert_diffs_equal(myers, after_step1);
    printf("verified\n");
    
    // 3. AFTER STEP 2 (optimize)
    SequenceDiffArray* after_step2 = create_diff_array(10);
    add_diff(after_step2, 0, 1, 0, 1);
    add_diff(after_step2, 2, 3, 2, 3);
    
    SequenceDiffArray* step2_actual = copy_diff_array(myers);
    optimize_sequence_diffs(seq1, seq2, step2_actual);
    print_sequence_diff_array("After Step 2 (optimize)", step2_actual);
    printf("  Step 2 (optimize): ");
    assert_diffs_equal(step2_actual, after_step2);
    printf("verified\n");
    
    // 4. AFTER STEP 3 (removeVeryShort)
    // NOT joined (gap > 4 non-whitespace chars)
    SequenceDiffArray* expected_final = create_diff_array(10);
    add_diff(expected_final, 0, 1, 0, 1);
    add_diff(expected_final, 2, 3, 2, 3);
    
    SequenceDiffArray* actual_final = copy_diff_array(step2_actual);
    remove_very_short_matching_lines_between_diffs(seq1, seq2, actual_final);
    print_sequence_diff_array("After Step 3 (removeVeryShort)", actual_final);
    printf("  Step 3 (removeVeryShort): ");
    assert_diffs_equal(actual_final, expected_final);
    printf("verified\n");
    
    printf("  ✓ Line optimization pipeline complete\n");
    
    // 5. CLEANUP
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    string_hash_map_destroy(hash_map);
    free_diff_array(myers);
    free_diff_array(after_step1);
    free_diff_array(step2_actual);
    free_diff_array(after_step2);
    free_diff_array(actual_final);
    free_diff_array(expected_final);
}

// ============================================================================
// TEST 4: Blank Line Separators (Should Join)
// ============================================================================

TEST(line_opt_blank_lines_join) {
    printf("=== Test 4: Blank Line Separators with Large Diff ===\n");
    
    // 1. SETUP
    // Make first diff large (4 lines each side = 8 total >5)
    const char* lines_a[] = {
        "old1", "old2", "old3", "old4",  // 4 lines
        "", "",  // 2 blank lines
        "old5"
    };
    const char* lines_b[] = {
        "new1", "new2", "new3", "new4",  // 4 lines  
        "", "",  // 2 blank lines
        "new5"
    };
    
    // 2. AFTER STEP 1 (Myers)
    SequenceDiffArray* after_step1 = create_diff_array(10);
    add_diff(after_step1, 0, 4, 0, 4);  // Modify 4 lines
    add_diff(after_step1, 6, 7, 6, 7);  // Modify 1 line
    
    StringHashMap* hash_map = string_hash_map_create();
    ISequence* seq1 = line_sequence_create(lines_a, 7, false, hash_map);
    ISequence* seq2 = line_sequence_create(lines_b, 7, false, hash_map);
    bool timeout = false;
    SequenceDiffArray* myers = run_step1_myers(seq1, seq2, &timeout);
    print_sequence_diff_array("After Step 1 (Myers)", myers);
    printf("  Step 1 (Myers): ");
    assert_diffs_equal(myers, after_step1);
    printf("verified\n");
    
    // 3. AFTER STEP 2 (optimize)
    SequenceDiffArray* after_step2 = create_diff_array(10);
    add_diff(after_step2, 0, 4, 0, 4);
    add_diff(after_step2, 6, 7, 6, 7);
    
    SequenceDiffArray* step2_actual = copy_diff_array(myers);
    optimize_sequence_diffs(seq1, seq2, step2_actual);
    print_sequence_diff_array("After Step 2 (optimize)", step2_actual);
    printf("  Step 2 (optimize): ");
    assert_diffs_equal(step2_actual, after_step2);
    printf("verified\n");
    
    // 4. AFTER STEP 3 (removeVeryShort)
    // JOINED! Two blank lines = 0 non-ws chars (≤4) AND first diff is large (4+4=8 >5)
    SequenceDiffArray* expected_final = create_diff_array(10);
    add_diff(expected_final, 0, 7, 0, 7);
    
    SequenceDiffArray* actual_final = copy_diff_array(step2_actual);
    remove_very_short_matching_lines_between_diffs(seq1, seq2, actual_final);
    print_sequence_diff_array("After Step 3 (removeVeryShort)", actual_final);
    printf("  Step 3 (removeVeryShort): ");
    assert_diffs_equal(actual_final, expected_final);
    printf("verified\n");
    
    printf("  ✓ Line optimization pipeline complete\n");
    
    // 5. CLEANUP
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    string_hash_map_destroy(hash_map);
    free_diff_array(myers);
    free_diff_array(after_step1);
    free_diff_array(step2_actual);
    free_diff_array(after_step2);
    free_diff_array(actual_final);
    free_diff_array(expected_final);
}

// ============================================================================
// TEST 5: Function Refactoring (Adjacent Changes Should Join)
// ============================================================================

TEST(line_opt_function_refactor) {
    printf("=== Test 5: Function Refactoring (Continuous Change) ===\n");
    
    // 1. SETUP
    const char* lines_a[] = {
        "function oldName() {",
        "  return 1;",
        "}"
    };
    const char* lines_b[] = {
        "function newName() {",
        "  return 2;",
        "}"
    };
    
    // 2. AFTER STEP 1 (Myers)
    // Myers sees lines 0-1 as different, line 2 as same
    // Result: ONE diff covering [0,2) since they're consecutive changes
    SequenceDiffArray* after_step1 = create_diff_array(10);
    add_diff(after_step1, 0, 2, 0, 2);
    
    StringHashMap* hash_map = string_hash_map_create();
    ISequence* seq1 = line_sequence_create(lines_a, 3, false, hash_map);
    ISequence* seq2 = line_sequence_create(lines_b, 3, false, hash_map);
    bool timeout = false;
    SequenceDiffArray* myers = run_step1_myers(seq1, seq2, &timeout);
    print_sequence_diff_array("After Step 1 (Myers)", myers);
    printf("  Step 1 (Myers): ");
    assert_diffs_equal(myers, after_step1);
    printf("verified\n");
    
    // 3. AFTER STEP 2 (optimize)
    // No change - it's a modification, not insertion/deletion
    SequenceDiffArray* after_step2 = create_diff_array(10);
    add_diff(after_step2, 0, 2, 0, 2);
    
    SequenceDiffArray* step2_actual = copy_diff_array(myers);
    optimize_sequence_diffs(seq1, seq2, step2_actual);
    print_sequence_diff_array("After Step 2 (optimize)", step2_actual);
    printf("  Step 2 (optimize): ");
    assert_diffs_equal(step2_actual, after_step2);
    printf("verified\n");
    
    // 4. AFTER STEP 3 (removeVeryShort)
    // Only 1 diff, nothing to join
    SequenceDiffArray* expected_final = create_diff_array(10);
    add_diff(expected_final, 0, 2, 0, 2);
    
    SequenceDiffArray* actual_final = copy_diff_array(step2_actual);
    remove_very_short_matching_lines_between_diffs(seq1, seq2, actual_final);
    print_sequence_diff_array("After Step 3 (removeVeryShort)", actual_final);
    printf("  Step 3 (removeVeryShort): ");
    assert_diffs_equal(actual_final, expected_final);
    printf("verified\n");
    
    printf("  ✓ Line optimization pipeline complete\n");
    printf("  ✓ Continuous change handled as single diff\n");
    
    // 5. CLEANUP
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    string_hash_map_destroy(hash_map);
    free_diff_array(myers);
    free_diff_array(after_step1);
    free_diff_array(step2_actual);
    free_diff_array(after_step2);
    free_diff_array(actual_final);
    free_diff_array(expected_final);
}

// ============================================================================
// TEST 6: Import Statement Changes (Adjacent, Should Join)
// ============================================================================

TEST(line_opt_import_changes) {
    printf("=== Test 6: Import Statement Changes (Continuous Change) ===\n");
    
    // 1. SETUP
    const char* lines_a[] = {
        "import { A } from 'lib';",
        "import { B } from 'lib';"
    };
    const char* lines_b[] = {
        "import { A, C } from 'lib';",
        "import { B, D } from 'lib';"
    };
    
    // 2. AFTER STEP 1 (Myers)
    // Both lines different, consecutive → ONE diff
    SequenceDiffArray* after_step1 = create_diff_array(10);
    add_diff(after_step1, 0, 2, 0, 2);
    
    StringHashMap* hash_map = string_hash_map_create();
    ISequence* seq1 = line_sequence_create(lines_a, 2, false, hash_map);
    ISequence* seq2 = line_sequence_create(lines_b, 2, false, hash_map);
    bool timeout = false;
    SequenceDiffArray* myers = run_step1_myers(seq1, seq2, &timeout);
    print_sequence_diff_array("After Step 1 (Myers)", myers);
    printf("  Step 1 (Myers): ");
    assert_diffs_equal(myers, after_step1);
    printf("verified\n");
    
    // 3. AFTER STEP 2 (optimize)
    // No change
    SequenceDiffArray* after_step2 = create_diff_array(10);
    add_diff(after_step2, 0, 2, 0, 2);
    
    SequenceDiffArray* step2_actual = copy_diff_array(myers);
    optimize_sequence_diffs(seq1, seq2, step2_actual);
    print_sequence_diff_array("After Step 2 (optimize)", step2_actual);
    printf("  Step 2 (optimize): ");
    assert_diffs_equal(step2_actual, after_step2);
    printf("verified\n");
    
    // 4. AFTER STEP 3 (removeVeryShort)
    // Only 1 diff, nothing to join
    SequenceDiffArray* expected_final = create_diff_array(10);
    add_diff(expected_final, 0, 2, 0, 2);
    
    SequenceDiffArray* actual_final = copy_diff_array(step2_actual);
    remove_very_short_matching_lines_between_diffs(seq1, seq2, actual_final);
    print_sequence_diff_array("After Step 3 (removeVeryShort)", actual_final);
    printf("  Step 3 (removeVeryShort): ");
    assert_diffs_equal(actual_final, expected_final);
    printf("verified\n");
    
    printf("  ✓ Line optimization pipeline complete\n");
    printf("  ✓ Continuous import changes handled as single diff\n");
    
    // 5. CLEANUP
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    string_hash_map_destroy(hash_map);
    free_diff_array(myers);
    free_diff_array(after_step1);
    free_diff_array(step2_actual);
    free_diff_array(after_step2);
    free_diff_array(actual_final);
    free_diff_array(expected_final);
}

// ============================================================================
// TEST 7: Comment Block Modification (Large Single Diff)
// ============================================================================

TEST(line_opt_comment_block) {
    printf("=== Test 7: Comment Block Modification ===\n");
    
    // 1. SETUP
    const char* lines_a[] = {
        "// Comment 1",
        "// Comment 2",
        "// Comment 3",
        "// Comment 4",
        "// Comment 5",
        "// Comment 6",
        "code line"
    };
    const char* lines_b[] = {
        "// Updated 1",
        "// Updated 2",
        "// Updated 3",
        "// Updated 4",
        "// Updated 5",
        "// Updated 6",
        "code line"
    };
    
    // 2. AFTER STEP 1 (Myers)
    SequenceDiffArray* after_step1 = create_diff_array(10);
    add_diff(after_step1, 0, 6, 0, 6);  // One big modification
    
    StringHashMap* hash_map = string_hash_map_create();
    ISequence* seq1 = line_sequence_create(lines_a, 7, false, hash_map);
    ISequence* seq2 = line_sequence_create(lines_b, 7, false, hash_map);
    bool timeout = false;
    SequenceDiffArray* myers = run_step1_myers(seq1, seq2, &timeout);
    print_sequence_diff_array("After Step 1 (Myers)", myers);
    printf("  Step 1 (Myers): ");
    assert_diffs_equal(myers, after_step1);
    printf("verified\n");
    
    // 3. AFTER STEP 2 (optimize)
    SequenceDiffArray* after_step2 = create_diff_array(10);
    add_diff(after_step2, 0, 6, 0, 6);
    
    SequenceDiffArray* step2_actual = copy_diff_array(myers);
    optimize_sequence_diffs(seq1, seq2, step2_actual);
    print_sequence_diff_array("After Step 2 (optimize)", step2_actual);
    printf("  Step 2 (optimize): ");
    assert_diffs_equal(step2_actual, after_step2);
    printf("verified\n");
    
    // 4. AFTER STEP 3 (removeVeryShort)
    // No change (already single diff)
    SequenceDiffArray* expected_final = create_diff_array(10);
    add_diff(expected_final, 0, 6, 0, 6);
    
    SequenceDiffArray* actual_final = copy_diff_array(step2_actual);
    remove_very_short_matching_lines_between_diffs(seq1, seq2, actual_final);
    print_sequence_diff_array("After Step 3 (removeVeryShort)", actual_final);
    printf("  Step 3 (removeVeryShort): ");
    assert_diffs_equal(actual_final, expected_final);
    printf("verified\n");
    
    printf("  ✓ Line optimization pipeline complete\n");
    
    // 5. CLEANUP
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    string_hash_map_destroy(hash_map);
    free_diff_array(myers);
    free_diff_array(after_step1);
    free_diff_array(step2_actual);
    free_diff_array(after_step2);
    free_diff_array(actual_final);
    free_diff_array(expected_final);
}

// ============================================================================
// TEST 8: Scattered Small Edits with Large Diff (Should Join)
// ============================================================================

TEST(line_opt_scattered_edits) {
    printf("=== Test 8: Small Gap with Large Diff (Should Join) ===\n");
    
    // 1. SETUP
    // Make first diff large (6 lines) so it triggers joining
    const char* lines_a[] = {
        "old1", "old2", "old3", "old4", "old5", "old6",  // 6 lines to change
        "x",  // 1 char gap
        "old7"
    };
    const char* lines_b[] = {
        "new1", "new2", "new3", "new4", "new5", "new6",  // 6 lines changed
        "x",  // 1 char gap
        "new7"
    };
    
    // 2. AFTER STEP 1 (Myers)
    SequenceDiffArray* after_step1 = create_diff_array(10);
    add_diff(after_step1, 0, 6, 0, 6);  // Modify 6 lines
    add_diff(after_step1, 7, 8, 7, 8);  // Modify 1 line
    
    StringHashMap* hash_map = string_hash_map_create();
    ISequence* seq1 = line_sequence_create(lines_a, 8, false, hash_map);
    ISequence* seq2 = line_sequence_create(lines_b, 8, false, hash_map);
    bool timeout = false;
    SequenceDiffArray* myers = run_step1_myers(seq1, seq2, &timeout);
    print_sequence_diff_array("After Step 1 (Myers)", myers);
    printf("  Step 1 (Myers): ");
    assert_diffs_equal(myers, after_step1);
    printf("verified\n");
    
    // 3. AFTER STEP 2 (optimize)
    SequenceDiffArray* after_step2 = create_diff_array(10);
    add_diff(after_step2, 0, 6, 0, 6);
    add_diff(after_step2, 7, 8, 7, 8);
    
    SequenceDiffArray* step2_actual = copy_diff_array(myers);
    optimize_sequence_diffs(seq1, seq2, step2_actual);
    print_sequence_diff_array("After Step 2 (optimize)", step2_actual);
    printf("  Step 2 (optimize): ");
    assert_diffs_equal(step2_actual, after_step2);
    printf("verified\n");
    
    // 4. AFTER STEP 3 (removeVeryShort)
    // JOINED! Gap "x" has 1 char (≤4) AND first diff is large (6+6=12 >5)
    SequenceDiffArray* expected_final = create_diff_array(10);
    add_diff(expected_final, 0, 8, 0, 8);
    
    SequenceDiffArray* actual_final = copy_diff_array(step2_actual);
    remove_very_short_matching_lines_between_diffs(seq1, seq2, actual_final);
    print_sequence_diff_array("After Step 3 (removeVeryShort)", actual_final);
    printf("  Step 3 (removeVeryShort): ");
    assert_diffs_equal(actual_final, expected_final);
    printf("verified\n");
    
    printf("  ✓ Line optimization pipeline complete\n");
    printf("  ✓ Large diff causes joining across small gap\n");
    
    // 5. CLEANUP
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    string_hash_map_destroy(hash_map);
    free_diff_array(myers);
    free_diff_array(after_step1);
    free_diff_array(step2_actual);
    free_diff_array(after_step2);
    free_diff_array(actual_final);
    free_diff_array(expected_final);
}

// ============================================================================
// TEST 9: Mixed Insertions and Modifications
// ============================================================================

TEST(line_opt_mixed_changes) {
    printf("=== Test 9: Mixed Insertions and Modifications ===\n");
    
    // 1. SETUP
    const char* lines_a[] = {
        "function test() {",
        "  let x = 1;",
        "  return x;",
        "}"
    };
    const char* lines_b[] = {
        "function test() {",
        "  let x = 1;",
        "  console.log(x);",  // INSERTED
        "  return x * 2;",     // MODIFIED
        "}"
    };
    
    // 2. AFTER STEP 1 (Myers)
    // Myers sees: replace 1 line with 2 lines
    SequenceDiffArray* after_step1 = create_diff_array(10);
    add_diff(after_step1, 2, 3, 2, 4);
    
    StringHashMap* hash_map = string_hash_map_create();
    ISequence* seq1 = line_sequence_create(lines_a, 4, false, hash_map);
    ISequence* seq2 = line_sequence_create(lines_b, 5, false, hash_map);
    bool timeout = false;
    SequenceDiffArray* myers = run_step1_myers(seq1, seq2, &timeout);
    print_sequence_diff_array("After Step 1 (Myers)", myers);
    printf("  Step 1 (Myers): ");
    assert_diffs_equal(myers, after_step1);
    printf("verified\n");
    
    // 3. AFTER STEP 2 (optimize)
    // No change (already optimal)
    SequenceDiffArray* after_step2 = create_diff_array(10);
    add_diff(after_step2, 2, 3, 2, 4);
    
    SequenceDiffArray* step2_actual = copy_diff_array(myers);
    optimize_sequence_diffs(seq1, seq2, step2_actual);
    print_sequence_diff_array("After Step 2 (optimize)", step2_actual);
    printf("  Step 2 (optimize): ");
    assert_diffs_equal(step2_actual, after_step2);
    printf("verified\n");
    
    // 4. AFTER STEP 3 (removeVeryShort)
    // Only 1 diff, nothing to join
    SequenceDiffArray* expected_final = create_diff_array(10);
    add_diff(expected_final, 2, 3, 2, 4);
    
    SequenceDiffArray* actual_final = copy_diff_array(step2_actual);
    remove_very_short_matching_lines_between_diffs(seq1, seq2, actual_final);
    print_sequence_diff_array("After Step 3 (removeVeryShort)", actual_final);
    printf("  Step 3 (removeVeryShort): ");
    assert_diffs_equal(actual_final, expected_final);
    printf("verified\n");
    
    printf("  ✓ Line optimization pipeline complete\n");
    printf("  ✓ Insertion+modification handled as single diff\n");
    
    // 5. CLEANUP
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    string_hash_map_destroy(hash_map);
    free_diff_array(myers);
    free_diff_array(after_step1);
    free_diff_array(step2_actual);
    free_diff_array(after_step2);
    free_diff_array(actual_final);
    free_diff_array(expected_final);
}

// ============================================================================
// TEST 10: Multi-Line String Change (Continuous Change)
// ============================================================================

TEST(line_opt_multiline_string) {
    printf("=== Test 10: Multi-Line String Change ===\n");
    
    // 1. SETUP
    const char* lines_a[] = {
        "const msg = `",
        "  Old line 1",
        "  Old line 2",
        "`;",
        "other code"
    };
    const char* lines_b[] = {
        "const msg = `",
        "  New line 1",
        "  New line 2",
        "`;",
        "other code"
    };
    
    // 2. AFTER STEP 1 (Myers)
    // Lines 1-2 are consecutive changes → ONE diff
    SequenceDiffArray* after_step1 = create_diff_array(10);
    add_diff(after_step1, 1, 3, 1, 3);
    
    StringHashMap* hash_map = string_hash_map_create();
    ISequence* seq1 = line_sequence_create(lines_a, 5, false, hash_map);
    ISequence* seq2 = line_sequence_create(lines_b, 5, false, hash_map);
    bool timeout = false;
    SequenceDiffArray* myers = run_step1_myers(seq1, seq2, &timeout);
    print_sequence_diff_array("After Step 1 (Myers)", myers);
    printf("  Step 1 (Myers): ");
    assert_diffs_equal(myers, after_step1);
    printf("verified\n");
    
    // 3. AFTER STEP 2 (optimize)
    // No change
    SequenceDiffArray* after_step2 = create_diff_array(10);
    add_diff(after_step2, 1, 3, 1, 3);
    
    SequenceDiffArray* step2_actual = copy_diff_array(myers);
    optimize_sequence_diffs(seq1, seq2, step2_actual);
    print_sequence_diff_array("After Step 2 (optimize)", step2_actual);
    printf("  Step 2 (optimize): ");
    assert_diffs_equal(step2_actual, after_step2);
    printf("verified\n");
    
    // 4. AFTER STEP 3 (removeVeryShort)
    // Only 1 diff, nothing to join
    SequenceDiffArray* expected_final = create_diff_array(10);
    add_diff(expected_final, 1, 3, 1, 3);
    
    SequenceDiffArray* actual_final = copy_diff_array(step2_actual);
    remove_very_short_matching_lines_between_diffs(seq1, seq2, actual_final);
    print_sequence_diff_array("After Step 3 (removeVeryShort)", actual_final);
    printf("  Step 3 (removeVeryShort): ");
    assert_diffs_equal(actual_final, expected_final);
    printf("verified\n");
    
    printf("  ✓ Line optimization pipeline complete\n");
    printf("  ✓ Continuous multi-line change handled as single diff\n");
    
    // 5. CLEANUP
    seq1->destroy(seq1);
    seq2->destroy(seq2);
    string_hash_map_destroy(hash_map);
    free_diff_array(myers);
    free_diff_array(after_step1);
    free_diff_array(step2_actual);
    free_diff_array(after_step2);
    free_diff_array(actual_final);
    free_diff_array(expected_final);
}

// ============================================================================
// Main Test Runner
// ============================================================================

int main(void) {
    printf("\n");
    printf("=======================================================\n");
    printf("  Line-Level Optimization Tests (Steps 1+2+3)\n");
    printf("=======================================================\n");
    printf("\n");
    
    RUN_TEST(line_opt_simple_addition);
    RUN_TEST(line_opt_small_gap_join);
    RUN_TEST(line_opt_large_gap_no_join);
    RUN_TEST(line_opt_blank_lines_join);
    RUN_TEST(line_opt_function_refactor);
    RUN_TEST(line_opt_import_changes);
    RUN_TEST(line_opt_comment_block);
    RUN_TEST(line_opt_scattered_edits);
    RUN_TEST(line_opt_mixed_changes);
    RUN_TEST(line_opt_multiline_string);
    
    printf("\n");
    printf("=======================================================\n");
    printf("  ALL LINE OPTIMIZATION TESTS PASSED ✓\n");
    printf("=======================================================\n");
    printf("\n");
    
    return 0;
}
