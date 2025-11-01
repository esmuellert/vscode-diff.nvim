/**
 * Common Test Utilities
 * 
 * Shared helper functions and macros for all test files.
 * Extracted from test_myers.c and test_optimize.c to avoid duplication.
 */

#ifndef TEST_UTILS_H
#define TEST_UTILS_H

#include "../include/types.h"
#include "../include/sequence.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

// ============================================================================
// Test Helper Macros
// ============================================================================

/**
 * Define a test function with standard signature
 */
#define TEST(name) static void test_##name(void)

/**
 * Run a test function with standard output
 */
#define RUN_TEST(name) do { \
    printf("Running test_%s...\n", #name); \
    test_##name(); \
    printf("  ✓ PASSED\n"); \
} while(0)

/**
 * Helper macro for validating a single diff in an array
 * Makes test code more readable
 * 
 * Usage: ASSERT_DIFF(result, 0, 1,2, 1,2);  // diff[0] = seq1[1,2) -> seq2[1,2)
 */
#define ASSERT_DIFF(result, index, s1_start, s1_end, s2_start, s2_end) \
    assert_diff_equals(&(result)->diffs[index], s1_start, s1_end, s2_start, s2_end, index)

// ============================================================================
// SequenceDiff Array Helpers
// ============================================================================

/**
 * Validate a single SequenceDiff has expected values
 * 
 * @param diff The diff to validate
 * @param expected_seq1_start Expected start in sequence 1
 * @param expected_seq1_end Expected end in sequence 1
 * @param expected_seq2_start Expected start in sequence 2
 * @param expected_seq2_end Expected end in sequence 2
 * @param diff_index Index of this diff (for error messages)
 */
static inline void assert_diff_equals(const SequenceDiff* diff,
                                      int expected_seq1_start, int expected_seq1_end,
                                      int expected_seq2_start, int expected_seq2_end,
                                      int diff_index) {
    if (diff->seq1_start != expected_seq1_start) {
        printf("  ✗ FAIL: diff[%d].seq1_start = %d, expected %d\n", 
               diff_index, diff->seq1_start, expected_seq1_start);
        assert(0);
    }
    if (diff->seq1_end != expected_seq1_end) {
        printf("  ✗ FAIL: diff[%d].seq1_end = %d, expected %d\n",
               diff_index, diff->seq1_end, expected_seq1_end);
        assert(0);
    }
    if (diff->seq2_start != expected_seq2_start) {
        printf("  ✗ FAIL: diff[%d].seq2_start = %d, expected %d\n",
               diff_index, diff->seq2_start, expected_seq2_start);
        assert(0);
    }
    if (diff->seq2_end != expected_seq2_end) {
        printf("  ✗ FAIL: diff[%d].seq2_end = %d, expected %d\n",
               diff_index, diff->seq2_end, expected_seq2_end);
        assert(0);
    }
}

/**
 * Validate the entire diff array count
 * 
 * @param result The diff array to validate
 * @param expected_count Expected number of diffs
 */
static inline void assert_diff_count(const SequenceDiffArray* result, int expected_count) {
    fflush(stdout);
    if (result->count != expected_count) {
        printf("  ✗ FAIL: diff count = %d, expected %d\n",
               result->count, expected_count);
        fflush(stdout);
        assert(0);
    }
}

/**
 * Create a SequenceDiffArray with specified capacity
 */
static inline SequenceDiffArray* create_diff_array(int capacity) {
    SequenceDiffArray* arr = (SequenceDiffArray*)malloc(sizeof(SequenceDiffArray));
    arr->diffs = (SequenceDiff*)malloc(sizeof(SequenceDiff) * capacity);
    arr->count = 0;
    arr->capacity = capacity;
    return arr;
}

/**
 * Add a diff to a SequenceDiffArray
 */
static inline void add_diff(SequenceDiffArray* arr, 
                           int s1_start, int s1_end, 
                           int s2_start, int s2_end) {
    assert(arr->count < arr->capacity);
    arr->diffs[arr->count].seq1_start = s1_start;
    arr->diffs[arr->count].seq1_end = s1_end;
    arr->diffs[arr->count].seq2_start = s2_start;
    arr->diffs[arr->count].seq2_end = s2_end;
    arr->count++;
}

/**
 * Free a diff array
 */
static inline void free_diff_array(SequenceDiffArray* arr) {
    if (arr) {
        free(arr->diffs);
        free(arr);
    }
}

static inline SequenceDiffArray* copy_diff_array(const SequenceDiffArray* src) {
    if (!src) return NULL;
    
    SequenceDiffArray* copy = (SequenceDiffArray*)malloc(sizeof(SequenceDiffArray));
    copy->capacity = src->capacity;
    copy->count = src->count;
    copy->diffs = (SequenceDiff*)malloc(sizeof(SequenceDiff) * src->capacity);
    
    for (int i = 0; i < src->count; i++) {
        copy->diffs[i] = src->diffs[i];
    }
    
    return copy;
}

static inline void assert_diffs_equal(const SequenceDiffArray* actual, 
                                       const SequenceDiffArray* expected) {
    assert_diff_count(actual, expected->count);
    for (int i = 0; i < expected->count; i++) {
        ASSERT_DIFF(actual, i, 
                   expected->diffs[i].seq1_start, expected->diffs[i].seq1_end,
                   expected->diffs[i].seq2_start, expected->diffs[i].seq2_end);
    }
}

// ============================================================================
// Step 1 Helper (Myers Algorithm Only - No Optimization)
// ============================================================================

// Forward declarations to avoid circular includes
struct ISequence;
typedef struct ISequence ISequence;

/**
 * Run Step 1 (Myers O(ND) diff) ONLY - no optimization
 * 
 * This is the pure Myers algorithm without any optimizations from Steps 2-3.
 * Use this in tests that need to verify Step 1 output before optimization.
 * 
 * NOTE: This uses O(ND) for all sizes (no DP fallback) for test simplicity.
 * For production use, use compute_line_alignments() which includes all steps.
 */
extern SequenceDiffArray* myers_nd_diff_algorithm(const ISequence* seq1, const ISequence* seq2,
                                                  int timeout_ms, bool* hit_timeout);

static inline SequenceDiffArray* run_step1_myers(
    const ISequence* seq1, const ISequence* seq2, 
    bool* hit_timeout) {
    return myers_nd_diff_algorithm(seq1, seq2, 5000, hit_timeout);
}

#endif // TEST_UTILS_H
