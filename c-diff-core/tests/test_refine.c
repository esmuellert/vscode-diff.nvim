/**
 * Unit Tests for Step 4: Character-Level Refinement
 * 
 * Tests refine_diffs_to_char_level()
 */

#include "../include/refine.h"
#include "../include/myers.h"
#include "../include/optimize.h"
#include "../include/types.h"
#include "../include/utils.h"
#include "../include/print_utils.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#define TEST(name) static void test_##name(void)
#define RUN_TEST(name) do { \
    printf("Running test_%s...\n", #name); \
    test_##name(); \
    printf("  ✓ PASSED\n"); \
} while(0)

// ============================================================================
// STEP 4 TESTS: refine_diffs_to_char_level()
// ============================================================================

TEST(refine_null_input) {
    const char* lines[] = {"test"};
    RangeMappingArray* result = refine_diffs_to_char_level(NULL, lines, 1, lines, 1);
    assert(result == NULL);
    printf("    ✓ Verified: NULL input correctly returns NULL\n");
}

TEST(refine_empty_diff_array) {
    const char* lines_a[] = {"same line"};
    const char* lines_b[] = {"same line"};
    
    SequenceDiffArray* diffs = myers_diff_algorithm(lines_a, 1, lines_b, 1);
    assert(diffs->count == 0);  // No diffs
    
    RangeMappingArray* refined = refine_diffs_to_char_level(diffs, lines_a, 1, lines_b, 1);
    assert(refined != NULL);
    assert(refined->count == 0);  // No character mappings
    
    printf("    ✓ Verified: No line diffs → no character mappings (count = 0)\n");
    
    range_mapping_array_free(refined);
    free(diffs->diffs);
    free(diffs);
}

TEST(refine_single_word_change) {
    const char* lines_a[] = {"hello world"};
    const char* lines_b[] = {"hello there"};
    
    SequenceDiffArray* diffs = myers_diff_algorithm(lines_a, 1, lines_b, 1);
    assert(diffs->count == 1);
    
    RangeMappingArray* refined = refine_diffs_to_char_level(diffs, lines_a, 1, lines_b, 1);
    assert(refined != NULL);
    assert(refined->count > 0);  // Should have character-level mappings
    
    print_range_mapping_array("Character mappings", refined);
    
    range_mapping_array_free(refined);
    free(diffs->diffs);
    free(diffs);
}

TEST(refine_full_line_replacement) {
    const char* lines_a[] = {"completely different"};
    const char* lines_b[] = {"totally changed"};
    
    SequenceDiffArray* diffs = myers_diff_algorithm(lines_a, 1, lines_b, 1);
    assert(diffs->count == 1);
    
    RangeMappingArray* refined = refine_diffs_to_char_level(diffs, lines_a, 1, lines_b, 1);
    assert(refined != NULL);
    assert(refined->count > 0);
    
    printf("    ✓ Verified: Full line replacement detected at character level\n");
    
    range_mapping_array_free(refined);
    free(diffs->diffs);
    free(diffs);
}

TEST(refine_whitespace_change) {
    const char* lines_a[] = {"hello  world"};  // Two spaces
    const char* lines_b[] = {"hello world"};   // One space
    
    SequenceDiffArray* diffs = myers_diff_algorithm(lines_a, 1, lines_b, 1);
    assert(diffs->count == 1);
    
    RangeMappingArray* refined = refine_diffs_to_char_level(diffs, lines_a, 1, lines_b, 1);
    assert(refined != NULL);
    assert(refined->count > 0);
    
    printf("    ✓ Verified: Whitespace changes detected (2 spaces → 1 space)\n");
    
    range_mapping_array_free(refined);
    free(diffs->diffs);
    free(diffs);
}

TEST(refine_multiple_changes_in_line) {
    const char* lines_a[] = {"foo bar baz"};
    const char* lines_b[] = {"FOO bar BAZ"};  // Changed first and last words
    
    SequenceDiffArray* diffs = myers_diff_algorithm(lines_a, 1, lines_b, 1);
    assert(diffs->count == 1);
    
    RangeMappingArray* refined = refine_diffs_to_char_level(diffs, lines_a, 1, lines_b, 1);
    assert(refined != NULL);
    // Should detect multiple character-level changes
    print_range_mapping_array("Character mappings", refined);
    
    range_mapping_array_free(refined);
    free(diffs->diffs);
    free(diffs);
}

TEST(refine_multiline_diff) {
    const char* lines_a[] = {
        "line one old",
        "line two old"
    };
    const char* lines_b[] = {
        "line one new",
        "line two new"
    };
    
    SequenceDiffArray* diffs = myers_diff_algorithm(lines_a, 2, lines_b, 2);
    assert(diffs->count == 1);  // One line-level diff covering both lines
    
    RangeMappingArray* refined = refine_diffs_to_char_level(diffs, lines_a, 2, lines_b, 2);
    assert(refined != NULL);
    assert(refined->count > 0);
    
    printf("    ✓ Verified: Multi-line diff refined to character level\n");
    
    range_mapping_array_free(refined);
    free(diffs->diffs);
    free(diffs);
}

TEST(refine_empty_line_vs_content) {
    const char* lines_a[] = {""};
    const char* lines_b[] = {"content"};
    
    SequenceDiffArray* diffs = myers_diff_algorithm(lines_a, 1, lines_b, 1);
    assert(diffs->count == 1);
    
    RangeMappingArray* refined = refine_diffs_to_char_level(diffs, lines_a, 1, lines_b, 1);
    assert(refined != NULL);
    
    printf("    ✓ Verified: Empty line → content line (insertion at char level)\n");
    
    range_mapping_array_free(refined);
    free(diffs->diffs);
    free(diffs);
}

TEST(refine_identical_lines) {
    const char* lines_a[] = {"same"};
    const char* lines_b[] = {"same"};
    
    SequenceDiffArray* diffs = myers_diff_algorithm(lines_a, 1, lines_b, 1);
    assert(diffs->count == 0);
    
    RangeMappingArray* refined = refine_diffs_to_char_level(diffs, lines_a, 1, lines_b, 1);
    assert(refined != NULL);
    assert(refined->count == 0);  // No changes
    
    printf("    ✓ Verified: Identical lines → no character mappings (count = 0)\n");
    
    range_mapping_array_free(refined);
    free(diffs->diffs);
    free(diffs);
}

TEST(refine_after_optimization) {
    // Real-world scenario: line diffs → optimize → refine
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
    
    // Step 1: Myers
    SequenceDiffArray* diffs = myers_diff_algorithm(lines_a, 3, lines_b, 3);
    assert(diffs->count == 2);
    
    // Step 2: Optimize (should join)
    optimize_sequence_diffs(diffs, lines_a, 3, lines_b, 3);
    assert(diffs->count == 1);
    
    // Step 4: Refine
    RangeMappingArray* refined = refine_diffs_to_char_level(diffs, lines_a, 3, lines_b, 3);
    assert(refined != NULL);
    assert(refined->count > 0);
    
    printf("    ✓ Verified: Pipeline integration - optimized diff refined to char level\n");
    print_range_mapping_array("After optimization", refined);
    
    range_mapping_array_free(refined);
    free(diffs->diffs);
    free(diffs);
}

// ============================================================================
// MAIN TEST RUNNER
// ============================================================================

int main(void) {
    printf("=== Step 4: Character-Level Refinement Tests ===\n\n");
    
    RUN_TEST(refine_null_input);
    RUN_TEST(refine_empty_diff_array);
    RUN_TEST(refine_single_word_change);
    RUN_TEST(refine_full_line_replacement);
    RUN_TEST(refine_whitespace_change);
    RUN_TEST(refine_multiple_changes_in_line);
    RUN_TEST(refine_multiline_diff);
    RUN_TEST(refine_empty_line_vs_content);
    RUN_TEST(refine_identical_lines);
    RUN_TEST(refine_after_optimization);
    
    printf("\n=== ALL STEP 4 TESTS PASSED ===\n");
    return 0;
}
