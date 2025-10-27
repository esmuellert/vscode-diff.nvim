/**
 * Test Suite for compute_diff() - Main Diff Orchestrator
 * 
 * Tests the complete diff pipeline including:
 * - Line-level diff computation
 * - Character-level refinement
 * - Whitespace change detection
 * - Line mapping conversion
 * 
 * VSCode Parity: Tests match VSCode's DefaultLinesDiffComputer behavior
 */

#include "../include/default_lines_diff_computer.h"
#include "../include/print_utils.h"
#include <stdio.h>
#include <string.h>

// ============================================================================
// Test Infrastructure
// ============================================================================

#define ASSERT(cond, msg) \
    do { \
        if (!(cond)) { \
            printf("  ✗ ASSERTION FAILED: %s\n", msg); \
            return false; \
        } \
    } while (0)

#define ASSERT_EQ(a, b, msg) \
    do { \
        if ((a) != (b)) { \
            printf("  ✗ ASSERTION FAILED: %s (expected %d, got %d)\n", msg, (int)(b), (int)(a)); \
            return false; \
        } \
    } while (0)

static void print_lines_diff(const LinesDiff* diff) {
    printf("\n");
    printf("  LinesDiff Result:\n");
    printf("    Changes: %d\n", diff->changes.count);
    printf("    Moves: %d\n", diff->moves.count);
    printf("    Hit timeout: %s\n", diff->hit_timeout ? "true" : "false");
    printf("\n");
    
    if (diff->changes.count > 0) {
        print_detailed_line_range_mapping_array("  Detailed Changes", &diff->changes);
    }
    printf("\n");
}

// ============================================================================
// Test Cases
// ============================================================================

bool test_empty_diff() {
    printf("Running test_empty_diff...\n");
    
    const char* original[] = {"hello"};
    const char* modified[] = {"hello"};
    
    DiffOptions options = {
        .ignore_trim_whitespace = false,
        .max_computation_time_ms = 0,
        .compute_moves = false,
        .extend_to_subwords = false
    };
    
    LinesDiff* result = compute_diff(original, 1, modified, 1, &options);
    
    ASSERT(result != NULL, "Result should not be NULL");
    ASSERT_EQ(result->changes.count, 0, "Should have 0 changes for identical files");
    ASSERT_EQ(result->moves.count, 0, "Should have 0 moves");
    ASSERT(result->hit_timeout == false, "Should not hit timeout");
    
    print_lines_diff(result);
    
    free_lines_diff(result);
    
    printf("  ✓ PASSED\n");
    return true;
}

bool test_simple_change() {
    printf("Running test_simple_change...\n");
    
    const char* original[] = {"hello world"};
    const char* modified[] = {"hello universe"};
    
    DiffOptions options = {
        .ignore_trim_whitespace = false,
        .max_computation_time_ms = 0,
        .compute_moves = false,
        .extend_to_subwords = false
    };
    
    LinesDiff* result = compute_diff(original, 1, modified, 1, &options);
    
    ASSERT(result != NULL, "Result should not be NULL");
    ASSERT_EQ(result->changes.count, 1, "Should have 1 change");
    ASSERT_EQ(result->changes.mappings[0].original.start_line, 1, "Original line 1");
    ASSERT_EQ(result->changes.mappings[0].modified.start_line, 1, "Modified line 1");
    ASSERT(result->changes.mappings[0].inner_change_count > 0, "Should have inner changes");
    
    print_lines_diff(result);
    
    free_lines_diff(result);
    
    printf("  ✓ PASSED\n");
    return true;
}

bool test_multiline_diff() {
    printf("Running test_multiline_diff...\n");
    
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
    
    DiffOptions options = {
        .ignore_trim_whitespace = false,
        .max_computation_time_ms = 0,
        .compute_moves = false,
        .extend_to_subwords = false
    };
    
    LinesDiff* result = compute_diff(original, 3, modified, 3, &options);
    
    ASSERT(result != NULL, "Result should not be NULL");
    
    print_lines_diff(result);
    
    free_lines_diff(result);
    
    printf("  ✓ PASSED\n");
    return true;
}

bool test_whitespace_changes() {
    printf("Running test_whitespace_changes...\n");
    
    const char* original[] = {
        "hello",
        "world"
    };
    const char* modified[] = {
        "  hello  ",
        "world"
    };
    
    DiffOptions options = {
        .ignore_trim_whitespace = false,  // Don't ignore whitespace
        .max_computation_time_ms = 0,
        .compute_moves = false,
        .extend_to_subwords = false
    };
    
    LinesDiff* result = compute_diff(original, 2, modified, 2, &options);
    
    ASSERT(result != NULL, "Result should not be NULL");
    // Should detect whitespace changes
    ASSERT(result->changes.count > 0, "Should detect whitespace changes");
    
    print_lines_diff(result);
    
    free_lines_diff(result);
    
    printf("  ✓ PASSED\n");
    return true;
}

bool test_ignore_whitespace() {
    printf("Running test_ignore_whitespace...\n");
    
    const char* original[] = {
        "hello",
        "world"
    };
    const char* modified[] = {
        "  hello  ",
        "world"
    };
    
    DiffOptions options = {
        .ignore_trim_whitespace = true,  // Ignore whitespace
        .max_computation_time_ms = 0,
        .compute_moves = false,
        .extend_to_subwords = false
    };
    
    LinesDiff* result = compute_diff(original, 2, modified, 2, &options);
    
    ASSERT(result != NULL, "Result should not be NULL");
    // Should ignore whitespace changes
    ASSERT_EQ(result->changes.count, 0, "Should ignore whitespace when option is set");
    
    print_lines_diff(result);
    
    free_lines_diff(result);
    
    printf("  ✓ PASSED\n");
    return true;
}

// ============================================================================
// Test Runner
// ============================================================================

int main(void) {
    printf("\n");
    printf("═══════════════════════════════════════════════════════════\n");
    printf("  compute_diff() Test Suite\n");
    printf("═══════════════════════════════════════════════════════════\n");
    printf("\n");
    
    int passed = 0;
    int total = 0;
    
    #define RUN_TEST(test) \
        do { \
            total++; \
            if (test()) passed++; \
            printf("\n"); \
        } while (0)
    
    RUN_TEST(test_empty_diff);
    RUN_TEST(test_simple_change);
    RUN_TEST(test_multiline_diff);
    RUN_TEST(test_whitespace_changes);
    RUN_TEST(test_ignore_whitespace);
    
    printf("═══════════════════════════════════════════════════════════\n");
    if (passed == total) {
        printf("  ✅ ALL TESTS PASSED (%d/%d)\n", passed, total);
    } else {
        printf("  ❌ SOME TESTS FAILED (%d/%d passed)\n", passed, total);
    }
    printf("═══════════════════════════════════════════════════════════\n");
    printf("\n");
    
    return (passed == total) ? 0 : 1;
}
