/**
 * Test Suite for Range Mapping Conversion
 * 
 * Tests the conversion of character-level RangeMappings to
 * line-level DetailedLineRangeMappings.
 * 
 * Functions Tested:
 * 1. line_range_join()
 * 2. line_range_intersects_or_touches()
 * 3. get_line_range_mapping()
 * 4. line_range_mapping_from_range_mappings()
 * 
 * Test Organization:
 * - Test helper functions individually
 * - Test main conversion with realistic scenarios
 * - Verify VSCode parity
 */

#include "../include/range_mapping.h"
#include "../include/types.h"
#include "../include/print_utils.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

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

// ============================================================================
// Helper Function Tests
// ============================================================================

bool test_line_range_join() {
    printf("Running test_line_range_join...\n");
    
    // Test 1: Join non-overlapping ranges
    LineRange a = {.start_line = 1, .end_line = 5};
    LineRange b = {.start_line = 10, .end_line = 15};
    LineRange result = line_range_join(a, b);
    
    ASSERT_EQ(result.start_line, 1, "Join should use min start");
    ASSERT_EQ(result.end_line, 15, "Join should use max end");
    
    // Test 2: Join overlapping ranges
    a = (LineRange){.start_line = 5, .end_line = 10};
    b = (LineRange){.start_line = 8, .end_line = 12};
    result = line_range_join(a, b);
    
    ASSERT_EQ(result.start_line, 5, "Join overlapping: min start");
    ASSERT_EQ(result.end_line, 12, "Join overlapping: max end");
    
    // Test 3: Join identical ranges
    a = (LineRange){.start_line = 1, .end_line = 5};
    b = (LineRange){.start_line = 1, .end_line = 5};
    result = line_range_join(a, b);
    
    ASSERT_EQ(result.start_line, 1, "Join identical: same start");
    ASSERT_EQ(result.end_line, 5, "Join identical: same end");
    
    printf("  ✓ PASSED\n");
    return true;
}

bool test_line_range_intersects_or_touches() {
    printf("Running test_line_range_intersects_or_touches...\n");
    
    // Test 1: Overlapping ranges
    LineRange a = {.start_line = 1, .end_line = 5};
    LineRange b = {.start_line = 3, .end_line = 7};
    ASSERT(line_range_intersects_or_touches(a, b), "Should intersect");
    
    // Test 2: Touching ranges (end touches start)
    a = (LineRange){.start_line = 1, .end_line = 5};
    b = (LineRange){.start_line = 5, .end_line = 10};
    ASSERT(line_range_intersects_or_touches(a, b), "Should touch (end to start)");
    
    // Test 3: Non-touching, non-overlapping
    a = (LineRange){.start_line = 1, .end_line = 5};
    b = (LineRange){.start_line = 10, .end_line = 15};
    ASSERT(!line_range_intersects_or_touches(a, b), "Should not touch/intersect");
    
    // Test 4: One inside another
    a = (LineRange){.start_line = 1, .end_line = 10};
    b = (LineRange){.start_line = 3, .end_line = 7};
    ASSERT(line_range_intersects_or_touches(a, b), "Should intersect (b inside a)");
    
    printf("  ✓ PASSED\n");
    return true;
}

// ============================================================================
// Main Conversion Function Tests
// ============================================================================

bool test_line_range_mapping_single_line_change() {
    printf("Running test_line_range_mapping_single_line_change...\n");
    
    /**
     * Scenario: Single word change on one line
     * Original: "hello world"
     * Modified: "hello universe"
     * 
     * Character mapping: (1,7)-(1,12) → (1,7)-(1,15)
     * Expected line mapping: Line 1 → Line 1
     */
    
    const char* original_lines[] = {"hello world"};
    const char* modified_lines[] = {"hello universe"};
    
    // Create RangeMapping for "world" → "universe"
    RangeMappingArray alignments;
    alignments.count = 1;
    alignments.capacity = 1;
    alignments.mappings = (RangeMapping*)malloc(sizeof(RangeMapping));
    
    alignments.mappings[0].original.start_line = 1;
    alignments.mappings[0].original.start_col = 7;
    alignments.mappings[0].original.end_line = 1;
    alignments.mappings[0].original.end_col = 12;
    
    alignments.mappings[0].modified.start_line = 1;
    alignments.mappings[0].modified.start_col = 7;
    alignments.mappings[0].modified.end_line = 1;
    alignments.mappings[0].modified.end_col = 15;
    
    printf("\n");
    print_range_mapping_array("Input RangeMappings", &alignments);
    
    // Convert to DetailedLineRangeMapping
    DetailedLineRangeMappingArray* result = line_range_mapping_from_range_mappings(
        &alignments, original_lines, 1, modified_lines, 1, false
    );
    
    printf("\n");
    print_detailed_line_range_mapping_array("Output DetailedLineRangeMappings", result);
    printf("\n");
    
    ASSERT(result != NULL, "Result should not be NULL");
    ASSERT_EQ(result->count, 1, "Should have 1 DetailedLineRangeMapping");
    
    // Verify line ranges
    ASSERT_EQ(result->mappings[0].original.start_line, 1, "Original should start at line 1");
    ASSERT_EQ(result->mappings[0].original.end_line, 2, "Original should end at line 2 (exclusive)");
    ASSERT_EQ(result->mappings[0].modified.start_line, 1, "Modified should start at line 1");
    ASSERT_EQ(result->mappings[0].modified.end_line, 2, "Modified should end at line 2 (exclusive)");
    
    // Verify inner changes preserved
    ASSERT_EQ(result->mappings[0].inner_change_count, 1, "Should have 1 inner change");
    ASSERT_EQ(result->mappings[0].inner_changes[0].original.start_col, 7, "Inner change start col");
    
    // Cleanup
    free(alignments.mappings);
    free_detailed_line_range_mapping_array(result);
    
    printf("  ✓ PASSED\n");
    return true;
}

bool test_line_range_mapping_multi_line_grouping() {
    printf("Running test_line_range_mapping_multi_line_grouping...\n");
    
    /**
     * Scenario: Multiple character changes that should be grouped
     * Original: 
     *   Line 1: "foo"
     *   Line 2: "bar"
     * Modified:
     *   Line 1: "FOO"
     *   Line 2: "BAR"
     * 
     * Two character mappings (line 1, line 2) should be grouped into
     * one DetailedLineRangeMapping covering both lines.
     */
    
    const char* original_lines[] = {"foo", "bar"};
    const char* modified_lines[] = {"FOO", "BAR"};
    
    // Create 2 RangeMappings (one for each line)
    RangeMappingArray alignments;
    alignments.count = 2;
    alignments.capacity = 2;
    alignments.mappings = (RangeMapping*)malloc(sizeof(RangeMapping) * 2);
    
    // Line 1: "foo" → "FOO"
    alignments.mappings[0].original.start_line = 1;
    alignments.mappings[0].original.start_col = 1;
    alignments.mappings[0].original.end_line = 1;
    alignments.mappings[0].original.end_col = 4;
    
    alignments.mappings[0].modified.start_line = 1;
    alignments.mappings[0].modified.start_col = 1;
    alignments.mappings[0].modified.end_line = 1;
    alignments.mappings[0].modified.end_col = 4;
    
    // Line 2: "bar" → "BAR"
    alignments.mappings[1].original.start_line = 2;
    alignments.mappings[1].original.start_col = 1;
    alignments.mappings[1].original.end_line = 2;
    alignments.mappings[1].original.end_col = 4;
    
    alignments.mappings[1].modified.start_line = 2;
    alignments.mappings[1].modified.start_col = 1;
    alignments.mappings[1].modified.end_line = 2;
    alignments.mappings[1].modified.end_col = 4;
    
    printf("\n");
    print_range_mapping_array("Input RangeMappings", &alignments);
    
    // Convert to DetailedLineRangeMapping
    DetailedLineRangeMappingArray* result = line_range_mapping_from_range_mappings(
        &alignments, original_lines, 2, modified_lines, 2, false
    );
    
    printf("\n");
    print_detailed_line_range_mapping_array("Output DetailedLineRangeMappings", result);
    printf("\n");
    
    ASSERT(result != NULL, "Result should not be NULL");
    ASSERT_EQ(result->count, 1, "Adjacent lines should be grouped into 1 mapping");
    
    // Verify grouped line range
    ASSERT_EQ(result->mappings[0].original.start_line, 1, "Grouped range starts at line 1");
    ASSERT_EQ(result->mappings[0].original.end_line, 3, "Grouped range ends at line 3 (exclusive)");
    ASSERT_EQ(result->mappings[0].modified.start_line, 1, "Modified starts at line 1");
    ASSERT_EQ(result->mappings[0].modified.end_line, 3, "Modified ends at line 3 (exclusive)");
    
    // Verify both inner changes preserved
    ASSERT_EQ(result->mappings[0].inner_change_count, 2, "Should have 2 inner changes");
    
    // Cleanup
    free(alignments.mappings);
    free_detailed_line_range_mapping_array(result);
    
    printf("  ✓ PASSED\n");
    return true;
}

// ============================================================================
// Main Test Runner
// ============================================================================

int main() {
    printf("═══════════════════════════════════════════════════════════\n");
    printf("  Range Mapping Conversion Test Suite\n");
    printf("═══════════════════════════════════════════════════════════\n\n");
    
    int passed = 0;
    int total = 0;
    
    // Helper function tests
    total++; if (test_line_range_join()) passed++;
    total++; if (test_line_range_intersects_or_touches()) passed++;
    
    // Main conversion tests
    total++; if (test_line_range_mapping_single_line_change()) passed++;
    total++; if (test_line_range_mapping_multi_line_grouping()) passed++;
    
    printf("\n═══════════════════════════════════════════════════════════\n");
    if (passed == total) {
        printf("  ✅ ALL TESTS PASSED (%d/%d)\n", passed, total);
        printf("═══════════════════════════════════════════════════════════\n");
        return 0;
    } else {
        printf("  ❌ SOME TESTS FAILED (%d/%d passed)\n", passed, total);
        printf("═══════════════════════════════════════════════════════════\n");
        return 1;
    }
}
