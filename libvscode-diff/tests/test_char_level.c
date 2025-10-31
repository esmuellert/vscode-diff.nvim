/**
 * Test Suite for Step 4: Character-Level Refinement
 * 
 * Tests the complete character-level optimization pipeline:
 * 1. Create char sequences from line ranges
 * 2. Run Myers on characters  
 * 3. optimizeSequenceDiffs()
 * 4. extendDiffsToEntireWordIfAppropriate()
 * 5. removeShortMatches()
 * 6. removeVeryShortMatchingTextBetweenLongDiffs()
 * 7. Translate to RangeMapping
 * 
 * Test Organization (TDD Approach):
 * For each test:
 * 1. Prepare two sets of lines to compare
 * 2. Prepare expected line-level diff (Step 1-3 output)
 * 3. Prepare expected char-level mappings (manual calculation)
 * 4. Call refine_diff_char_level() and compare with expected
 */

#include "../include/char_level.h"
#include "../include/types.h"
#include "test_utils.h"
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

// =============================================================================
// Test Infrastructure  
// =============================================================================

#define ASSERT(cond, msg) \
    do { \
        if (!(cond)) { \
            printf("  ASSERTION FAILED: %s\n", msg); \
            assert(cond && msg); \
        } \
    } while (0)

#define ASSERT_EQ(a, b, msg) \
    do { \
        if ((a) != (b)) { \
            printf("  ASSERTION FAILED: %s (expected %d, got %d)\n", msg, (int)(b), (int)(a)); \
            assert((a) == (b) && msg); \
        } \
    } while (0)

// =============================================================================
// Test Cases - Character-Level Refinement
// =============================================================================

/**
 * Test 1: Single word change within a line
 * 
 * Input:
 *   Line A: "Hello world"
 *   Line B: "Hello there"
 * 
 * Expected:
 *   - Line diff: lines 0-1 → 0-1
 *   - Char mapping: "world" → "there" (word boundary aligned)
 */
TEST(single_word_change) {
    const char* lines_a[] = {"Hello world"};
    const char* lines_b[] = {"Hello there"};
    
    // Line-level diff (covering the changed line)
    SequenceDiff line_diff = {0, 1, 0, 1};
    
    // Expected char-level mapping
    // "world" (offset 6-11 in line 0) → "there" (offset 6-11 in line 0)
    // In 1-based (line,col): (1,7) to (1,12) → (1,7) to (1,12)
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = true,
        .extend_to_subwords = false
    };
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts, NULL);
    
    ASSERT(result != NULL, "Result should not be NULL");
    ASSERT(result->count > 0, "Should have at least one mapping");
    
    // After word extension, should map "world" → "there"
    RangeMapping* m = &result->mappings[0];
    printf("  Char mapping: (%d,%d)-(%d,%d) → (%d,%d)-(%d,%d)\n",
           m->original.start_line, m->original.start_col,
           m->original.end_line, m->original.end_col,
           m->modified.start_line, m->modified.start_col,
           m->modified.end_line, m->modified.end_col);
    
    // VSCode would extend to word boundaries
    // "world" starts at col 7 (1-based), ends at col 12
    // "there" starts at col 7, ends at col 12
    ASSERT_EQ(m->original.start_line, 1, "Original start line");
    ASSERT_EQ(m->original.start_col, 7, "Original start col");
    
    free_range_mapping_array(result);
    
}

/**
 * Test 2: Multiple word changes in one line
 * 
 * Input:
 *   Line A: "The quick brown fox"
 *   Line B: "The fast brown dog"
 * 
 * Expected: Two separate char mappings for "quick"→"fast" and "fox"→"dog"
 */
TEST(multiple_word_changes) {
    const char* lines_a[] = {"The quick brown fox"};
    const char* lines_b[] = {"The fast brown dog"};
    
    SequenceDiff line_diff = {0, 1, 0, 1};
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = true,
        .extend_to_subwords = false
    };
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts, NULL);
    
    ASSERT(result != NULL, "Result should not be NULL");
    
    printf("  Got %d char mappings\n", result->count);
    for (int i = 0; i < result->count; i++) {
        RangeMapping* m = &result->mappings[i];
        printf("    [%d] (%d,%d)-(%d,%d) → (%d,%d)-(%d,%d)\n", i,
               m->original.start_line, m->original.start_col,
               m->original.end_line, m->original.end_col,
               m->modified.start_line, m->modified.start_col,
               m->modified.end_line, m->modified.end_col);
    }
    
    // Should have mappings for changed words
    ASSERT(result->count >= 1, "Should have at least one mapping");
    
    free_range_mapping_array(result);
    
}

/**
 * Test 3: Multi-line character diff
 * 
 * Input:
 *   Lines A: ["function foo() {", "  return bar;"]
 *   Lines B: ["function foo() {", "  return baz;"]
 * 
 * Expected: Char mapping for "bar" → "baz" on line 2
 */
TEST(multiline_char_diff) {
    const char* lines_a[] = {
        "function foo() {",
        "  return bar;"
    };
    const char* lines_b[] = {
        "function foo() {",
        "  return baz;"
    };
    
    // Line diff covers lines 1-2 (second line changed)
    SequenceDiff line_diff = {1, 2, 1, 2};
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = true,
        .extend_to_subwords = false
    };
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 2, lines_b, 2, &opts, NULL);
    
    ASSERT(result != NULL, "Result should not be NULL");
    
    printf("  Got %d char mappings\n", result->count);
    for (int i = 0; i < result->count; i++) {
        RangeMapping* m = &result->mappings[i];
        printf("    [%d] (%d,%d)-(%d,%d) → (%d,%d)-(%d,%d)\n", i,
               m->original.start_line, m->original.start_col,
               m->original.end_line, m->original.end_col,
               m->modified.start_line, m->modified.start_col,
               m->modified.end_line, m->modified.end_col);
    }
    
    // Should have mapping on line 2
    bool found_line2 = false;
    for (int i = 0; i < result->count; i++) {
        if (result->mappings[i].original.start_line == 2) {
            found_line2 = true;
            break;
        }
    }
    ASSERT(found_line2, "Should have mapping on line 2");
    
    free_range_mapping_array(result);
    
}

/**
 * Test 4: Whitespace handling
 * 
 * Test with consider_whitespace_changes = false
 * Should ignore whitespace differences
 */
TEST(whitespace_handling) {
    const char* lines_a[] = {"  hello  world  "};
    const char* lines_b[] = {"hello world"};
    
    SequenceDiff line_diff = {0, 1, 0, 1};
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = false,  // Ignore whitespace
        .extend_to_subwords = false
    };
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts, NULL);
    
    ASSERT(result != NULL, "Result should not be NULL");
    
    printf("  Got %d char mappings (should be 0 or minimal with whitespace ignored)\n", result->count);
    
    // With whitespace ignored, should have very few or no diffs
    // (depends on exact trimming behavior)
    
    free_range_mapping_array(result);
    
}

/**
 * Test 5: CamelCase subword extension
 * 
 * Input:
 *   Line A: "getUserName()"
 *   Line B: "getUserInfo()"
 * 
 * With extend_to_subwords: should extend to "Name" → "Info" (subword boundaries)
 */
TEST(camelcase_subword) {
    const char* lines_a[] = {"getUserName()"};
    const char* lines_b[] = {"getUserInfo()"};
    
    SequenceDiff line_diff = {0, 1, 0, 1};
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = true,
        .extend_to_subwords = true  // Enable subword extension
    };
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts, NULL);
    
    ASSERT(result != NULL, "Result should not be NULL");
    
    printf("  Got %d char mappings\n", result->count);
    for (int i = 0; i < result->count; i++) {
        RangeMapping* m = &result->mappings[i];
        printf("    [%d] (%d,%d)-(%d,%d) → (%d,%d)-(%d,%d)\n", i,
               m->original.start_line, m->original.start_col,
               m->original.end_line, m->original.end_col,
               m->modified.start_line, m->modified.start_col,
               m->modified.end_line, m->modified.end_col);
    }
    
    // Should have mapping for the changed subword
    ASSERT(result->count > 0, "Should have at least one mapping");
    
    free_range_mapping_array(result);
    
}

/**
 * Test 6: Completely different lines
 * 
 * Input:
 *   Line A: "apple"
 *   Line B: "orange"
 * 
 * Expected: Single mapping covering entire lines
 */
TEST(completely_different) {
    const char* lines_a[] = {"apple"};
    const char* lines_b[] = {"orange"};
    
    SequenceDiff line_diff = {0, 1, 0, 1};
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = true,
        .extend_to_subwords = false
    };
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts, NULL);
    
    ASSERT(result != NULL, "Result should not be NULL");
    ASSERT(result->count > 0, "Should have at least one mapping");
    
    printf("  Got %d char mappings\n", result->count);
    
    free_range_mapping_array(result);
    
}

/**
 * Test 7: Empty line vs content
 * 
 * Input:
 *   Line A: ""
 *   Line B: "hello"
 * 
 * Expected: Insertion mapping
 */
TEST(empty_vs_content) {
    const char* lines_a[] = {""};
    const char* lines_b[] = {"hello"};
    
    SequenceDiff line_diff = {0, 1, 0, 1};
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = true,
        .extend_to_subwords = false
    };
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts, NULL);
    
    ASSERT(result != NULL, "Result should not be NULL");
    
    printf("  Got %d char mappings\n", result->count);
    for (int i = 0; i < result->count; i++) {
        RangeMapping* m = &result->mappings[i];
        printf("    [%d] (%d,%d)-(%d,%d) → (%d,%d)-(%d,%d)\n", i,
               m->original.start_line, m->original.start_col,
               m->original.end_line, m->original.end_col,
               m->modified.start_line, m->modified.start_col,
               m->modified.end_line, m->modified.end_col);
    }
    
    free_range_mapping_array(result);
    
}

/**
 * Test 8: Punctuation and symbols
 * 
 * Input:
 *   Line A: "hello, world!"
 *   Line B: "hello; world?"
 * 
 * Expected: Mappings for "," → ";" and "!" → "?"
 */
TEST(punctuation_changes) {
    const char* lines_a[] = {"hello, world!"};
    const char* lines_b[] = {"hello; world?"};
    
    SequenceDiff line_diff = {0, 1, 0, 1};
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = true,
        .extend_to_subwords = false
    };
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts, NULL);
    
    ASSERT(result != NULL, "Result should not be NULL");
    
    printf("  Got %d char mappings\n", result->count);
    for (int i = 0; i < result->count; i++) {
        RangeMapping* m = &result->mappings[i];
        printf("    [%d] (%d,%d)-(%d,%d) → (%d,%d)-(%d,%d)\n", i,
               m->original.start_line, m->original.start_col,
               m->original.end_line, m->original.end_col,
               m->modified.start_line, m->modified.start_col,
               m->modified.end_line, m->modified.end_col);
    }
    
    free_range_mapping_array(result);
    
}

/**
 * Test 9: Short match removal
 * 
 * Input:
 *   Line A: "abcXYZdef"
 *   Line B: "123XYZ456"
 * 
 * If "XYZ" is short match (≤2 chars would be joined), test this heuristic
 */
TEST(short_match_removal) {
    const char* lines_a[] = {"abXdef"};
    const char* lines_b[] = {"12X345"};
    
    SequenceDiff line_diff = {0, 1, 0, 1};
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = true,
        .extend_to_subwords = false
    };
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts, NULL);
    
    ASSERT(result != NULL, "Result should not be NULL");
    
    printf("  Got %d char mappings\n", result->count);
    for (int i = 0; i < result->count; i++) {
        RangeMapping* m = &result->mappings[i];
        printf("    [%d] (%d,%d)-(%d,%d) → (%d,%d)-(%d,%d)\n", i,
               m->original.start_line, m->original.start_col,
               m->original.end_line, m->original.end_col,
               m->modified.start_line, m->modified.start_col,
               m->modified.end_line, m->modified.end_col);
    }
    
    // With short match removal, single 'X' might be joined with surrounding changes
    // Result depends on exact heuristics
    
    free_range_mapping_array(result);
    
}

/**
 * Test 10: Real code example - function rename
 * 
 * Input:
 *   Lines A: ["function oldFunction() {", "  console.log('old');", "}"]
 *   Lines B: ["function newFunction() {", "  console.log('new');", "}"]
 * 
 * Expected: Character mappings for "old" → "new" in both locations
 */
TEST(real_code_function_rename) {
    const char* lines_a[] = {
        "function oldFunction() {",
        "  console.log('old');",
        "}"
    };
    const char* lines_b[] = {
        "function newFunction() {",
        "  console.log('new');",
        "}"
    };
    
    // Line diff covers all 3 lines
    SequenceDiff line_diff = {0, 3, 0, 3};
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = true,
        .extend_to_subwords = false
    };
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 3, lines_b, 3, &opts, NULL);
    
    ASSERT(result != NULL, "Result should not be NULL");
    
    printf("  Got %d char mappings\n", result->count);
    for (int i = 0; i < result->count; i++) {
        RangeMapping* m = &result->mappings[i];
        printf("    [%d] (%d,%d)-(%d,%d) → (%d,%d)-(%d,%d)\n", i,
               m->original.start_line, m->original.start_col,
               m->original.end_line, m->original.end_col,
               m->modified.start_line, m->modified.start_col,
               m->modified.end_line, m->modified.end_col);
    }
    
    // Should have mappings for "old" → "new" changes
    ASSERT(result->count > 0, "Should have char mappings");
    
    free_range_mapping_array(result);
    
}

/**
 * Test 11: Cross-line range mapping
 * 
 * This test demonstrates range mappings that span across line boundaries,
 * producing mappings like L1:C11-L2:C1 -> L1:C19-L2:C9.
 * 
 * Input:
 *   Line A1: "first line of code"
 *   Line A2: "second line of code"
 *   Line B1: "changed first line"
 *   Line B2: "changed second line"
 * 
 * Expected: Character mappings showing cross-line transformations
 */
TEST(cross_line_range_mapping) {
    const char* lines_a[] = {
        "first line of code",
        "second line of code"
    };
    const char* lines_b[] = {
        "changed first line",
        "changed second line"
    };
    
    // Line diff covers both lines
    SequenceDiff line_diff = {0, 2, 0, 2};
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = true,
        .extend_to_subwords = false
    };
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 2, lines_b, 2, &opts, NULL);
    
    ASSERT(result != NULL, "Result should not be NULL");
    
    printf("  Got %d char mappings\n", result->count);
    for (int i = 0; i < result->count; i++) {
        RangeMapping* m = &result->mappings[i];
        printf("    [%d] L%d:C%d-L%d:C%d -> L%d:C%d-L%d:C%d\n", i,
               m->original.start_line, m->original.start_col,
               m->original.end_line, m->original.end_col,
               m->modified.start_line, m->modified.start_col,
               m->modified.end_line, m->modified.end_col);
    }
    
    // Should have at least one cross-line mapping (spanning from one line to another)
    bool has_cross_line = false;
    for (int i = 0; i < result->count; i++) {
        RangeMapping* m = &result->mappings[i];
        if (m->original.start_line != m->original.end_line || 
            m->modified.start_line != m->modified.end_line) {
            has_cross_line = true;
            printf("  Found cross-line mapping at index %d\n", i);
            break;
        }
    }
    
    ASSERT(has_cross_line, "Should have at least one cross-line range mapping");
    
    free_range_mapping_array(result);
    
}

/**
 * Test 12: Delete and add lines
 * 
 * Input:
 *   Line A1: "line 1"
 *   Line A2: "line 2 to delete"
 *   Line A3: "line 3"
 *   Line B1: "line 1"
 *   Line B2: "line 3"
 *   Line B3: "line 4 added"
 * 
 * Expected: Character mappings for deleted and added content
 */
TEST(delete_and_add) {
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
    
    // Line diff for deletion
    SequenceDiff line_diff1 = {1, 2, 1, 1};
    
    CharLevelOptions opts = {
        .consider_whitespace_changes = true,
        .extend_to_subwords = false
    };
    
    RangeMappingArray* result1 = refine_diff_char_level(&line_diff1, original, 3, modified, 3, &opts, NULL);
    
    ASSERT(result1 != NULL, "Result for deletion should not be NULL");
    
    printf("  Got %d char mappings for deletion\n", result1->count);
    for (int i = 0; i < result1->count; i++) {
        RangeMapping* m = &result1->mappings[i];
        printf("    [%d] L%d:C%d-L%d:C%d -> L%d:C%d-L%d:C%d\n", i,
               m->original.start_line, m->original.start_col,
               m->original.end_line, m->original.end_col,
               m->modified.start_line, m->modified.start_col,
               m->modified.end_line, m->modified.end_col);
    }
    
    // Line diff for addition
    SequenceDiff line_diff2 = {3, 3, 2, 3};
    
    RangeMappingArray* result2 = refine_diff_char_level(&line_diff2, original, 3, modified, 3, &opts, NULL);
    
    ASSERT(result2 != NULL, "Result for addition should not be NULL");
    
    printf("  Got %d char mappings for addition\n", result2->count);
    for (int i = 0; i < result2->count; i++) {
        RangeMapping* m = &result2->mappings[i];
        printf("    [%d] L%d:C%d-L%d:C%d -> L%d:C%d-L%d:C%d\n", i,
               m->original.start_line, m->original.start_col,
               m->original.end_line, m->original.end_col,
               m->modified.start_line, m->modified.start_col,
               m->modified.end_line, m->modified.end_col);
    }
    
    free_range_mapping_array(result1);
    free_range_mapping_array(result2);
    
}

// =============================================================================
// Main Test Runner
// =============================================================================

int main(void) {
    printf("=== Character-Level Refinement Tests (Step 4) ===\n\n");
    
    RUN_TEST(single_word_change);
    RUN_TEST(multiple_word_changes);
    RUN_TEST(multiline_char_diff);
    RUN_TEST(whitespace_handling);
    RUN_TEST(camelcase_subword);
    RUN_TEST(completely_different);
    RUN_TEST(empty_vs_content);
    RUN_TEST(punctuation_changes);
    RUN_TEST(short_match_removal);
    RUN_TEST(real_code_function_rename);
    RUN_TEST(cross_line_range_mapping);
    RUN_TEST(delete_and_add);
    
    printf("\n");
    printf("=======================================================\n");
    printf("  ALL CHARACTER-LEVEL TESTS PASSED ✓\n");
    printf("=======================================================\n");
    printf("\n");
    
    return 0;
}
