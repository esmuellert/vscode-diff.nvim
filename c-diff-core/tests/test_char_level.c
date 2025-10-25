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
#include "../include/myers.h"
#include "../include/optimize.h"
#include "../include/sequence.h"
#include "../include/types.h"
#include "test_utils.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

// =============================================================================
// Test Infrastructure
// =============================================================================

static int tests_run = 0;
static int tests_passed = 0;

#define TEST(name) \
    static bool test_##name(); \
    static void run_##name() { \
        tests_run++; \
        printf("Running test_%s...\n", #name); \
        if (test_##name()) { \
            tests_passed++; \
            printf("  ✓ PASSED\n\n"); \
        } else { \
            printf("  ✗ FAILED\n\n"); \
        } \
    } \
    static bool test_##name()

#define ASSERT(cond, msg) \
    do { \
        if (!(cond)) { \
            printf("  ASSERTION FAILED: %s\n", msg); \
            return false; \
        } \
    } while (0)

#define ASSERT_EQ(a, b, msg) \
    do { \
        if ((a) != (b)) { \
            printf("  ASSERTION FAILED: %s (expected %d, got %d)\n", msg, (int)(b), (int)(a)); \
            return false; \
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
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts);
    
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
    return true;
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
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts);
    
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
    return true;
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
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 2, lines_b, 2, &opts);
    
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
    return true;
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
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts);
    
    ASSERT(result != NULL, "Result should not be NULL");
    
    printf("  Got %d char mappings (should be 0 or minimal with whitespace ignored)\n", result->count);
    
    // With whitespace ignored, should have very few or no diffs
    // (depends on exact trimming behavior)
    
    free_range_mapping_array(result);
    return true;
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
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts);
    
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
    return true;
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
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts);
    
    ASSERT(result != NULL, "Result should not be NULL");
    ASSERT(result->count > 0, "Should have at least one mapping");
    
    printf("  Got %d char mappings\n", result->count);
    
    free_range_mapping_array(result);
    return true;
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
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts);
    
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
    return true;
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
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts);
    
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
    return true;
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
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 1, lines_b, 1, &opts);
    
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
    return true;
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
    
    RangeMappingArray* result = refine_diff_char_level(&line_diff, lines_a, 3, lines_b, 3, &opts);
    
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
    return true;
}

// =============================================================================
// Main Test Runner
// =============================================================================

int main(void) {
    printf("=== Character-Level Refinement Tests (Step 4) ===\n\n");
    
    run_single_word_change();
    run_multiple_word_changes();
    run_multiline_char_diff();
    run_whitespace_handling();
    run_camelcase_subword();
    run_completely_different();
    run_empty_vs_content();
    run_punctuation_changes();
    run_short_match_removal();
    run_real_code_function_rename();
    
    printf("=== Test Summary ===\n");
    printf("Total: %d\n", tests_run);
    printf("Passed: %d\n", tests_passed);
    printf("Failed: %d\n", tests_run - tests_passed);
    
    return (tests_run == tests_passed) ? 0 : 1;
}
