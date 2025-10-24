/**
 * Integration Test: VSCode Diff Algorithm Pipeline
 * 
 * Data-driven test framework - add new cases by just providing test data.
 * Single verification code, multiple test cases.
 * 
 * NOTATION: seq1[1,2) -> seq2[1,2)
 *   [1,2) = starts at 1, ends before 2 (exclusive end) = line 1 only
 *   Arrow = "these regions differ"
 */

#include "../include/myers.h"
#include "../include/optimize.h"
#include "../include/types.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

// ============================================================================
// EXPECTED RESULTS - Define what each step should produce
// ============================================================================

typedef struct {
    int seq1_start;
    int seq1_end;
    int seq2_start;
    int seq2_end;
} ExpectedDiff;

typedef struct {
    ExpectedDiff* diffs;
    int count;
} ExpectedResult;

// ============================================================================
// TEST CASE - Everything needed for one complete test
// ============================================================================

typedef struct {
    const char* name;
    const char** lines_a;
    int len_a;
    const char** lines_b;
    int len_b;
    ExpectedResult expected_myers;
    ExpectedResult expected_optimize;
    ExpectedResult expected_remove_short;
} TestCase;

// ============================================================================
// VERIFICATION HELPERS - Single set of verification code
// ============================================================================

static void verify_diff_array(SequenceDiffArray* actual, ExpectedResult* expected, 
                               const char* step_name) {
    // Check count
    if (actual->count != expected->count) {
        printf("  ✗ FAILED at %s: expected %d diffs, got %d\n", 
               step_name, expected->count, actual->count);
        assert(false);
    }
    
    // Check each diff's coordinates
    for (int i = 0; i < expected->count; i++) {
        SequenceDiff* a = &actual->diffs[i];
        ExpectedDiff* e = &expected->diffs[i];
        
        if (a->seq1_start != e->seq1_start || a->seq1_end != e->seq1_end ||
            a->seq2_start != e->seq2_start || a->seq2_end != e->seq2_end) {
            printf("  ✗ FAILED at %s diff[%d]:\n", step_name, i);
            printf("    Expected: seq1[%d,%d) -> seq2[%d,%d)\n",
                   e->seq1_start, e->seq1_end, e->seq2_start, e->seq2_end);
            printf("    Got:      seq1[%d,%d) -> seq2[%d,%d)\n",
                   a->seq1_start, a->seq1_end, a->seq2_start, a->seq2_end);
            assert(false);
        }
    }
}

static void print_diff_state(const char* step_name, SequenceDiffArray* diffs) {
    printf("  %s: %d diff(s)\n", step_name, diffs->count);
    for (int i = 0; i < diffs->count; i++) {
        printf("    [%d] seq1[%d,%d) -> seq2[%d,%d)\n", i,
               diffs->diffs[i].seq1_start, diffs->diffs[i].seq1_end,
               diffs->diffs[i].seq2_start, diffs->diffs[i].seq2_end);
    }
}

// ============================================================================
// PIPELINE RUNNER - Single function that runs all steps
// ============================================================================

static void run_test_case(TestCase* test) {
    printf("\n");
    printf("═══════════════════════════════════════════════════════════\n");
    printf("TEST: %s\n", test->name);
    printf("═══════════════════════════════════════════════════════════\n");
    
    // Step 1: Myers Algorithm
    SequenceDiffArray* diffs = myers_diff_algorithm(test->lines_a, test->len_a, 
                                                     test->lines_b, test->len_b);
    assert(diffs != NULL);
    print_diff_state("Step 1 (Myers)", diffs);
    verify_diff_array(diffs, &test->expected_myers, "Myers");
    
    // Step 2: Optimize
    bool ok = optimize_sequence_diffs(diffs, test->lines_a, test->len_a, 
                                      test->lines_b, test->len_b);
    assert(ok);
    print_diff_state("Step 2 (Optimize)", diffs);
    verify_diff_array(diffs, &test->expected_optimize, "Optimize");
    
    // Step 3: Remove Short Matches
    ok = remove_short_matches(diffs, test->lines_a, test->len_a, 
                              test->lines_b, test->len_b, 3);
    assert(ok);
    print_diff_state("Step 3 (Remove Short)", diffs);
    verify_diff_array(diffs, &test->expected_remove_short, "Remove Short");
    
    // Cleanup
    free(diffs->diffs);
    free(diffs);
    
    printf("✓ PASSED\n");
}

// ============================================================================
// TEST CASE DEFINITIONS - Just data, no duplicate code!
// ============================================================================

int main(void) {
    printf("\n");
    printf("╔═══════════════════════════════════════════════════════════╗\n");
    printf("║   VSCode Diff Algorithm - Integration Test Pipeline       ║\n");
    printf("╚═══════════════════════════════════════════════════════════╝\n");
    
    // ------------------------------------------------------------------------
    // TEST 1: Step 2 Joining - gap=2
    // ------------------------------------------------------------------------
    {
        const char* lines_a[] = {
            "function doWork() {",
            "  // First section - old",
            "  let x = 1;",
            "",
            "  // Second section - old",
            "  let y = 2;",
            "",
            "  return x + y;",
            "}"
        };
        
        const char* lines_b[] = {
            "function doWork() {",
            "  // First section - new",
            "  let x = 1;",
            "",
            "  // Second section - new",
            "  let y = 2;",
            "",
            "  return x + y;",
            "}"
        };
        
        ExpectedDiff myers_diffs[] = {
            {1, 2, 1, 2},
            {4, 5, 4, 5}
        };
        
        ExpectedDiff optimized_diffs[] = {
            {1, 5, 1, 5}  // Joined!
        };
        
        TestCase test = {
            .name = "Step 2 Join - Two changes with gap=2",
            .lines_a = lines_a,
            .len_a = 9,
            .lines_b = lines_b,
            .len_b = 9,
            .expected_myers = {myers_diffs, 2},
            .expected_optimize = {optimized_diffs, 1},
            .expected_remove_short = {optimized_diffs, 1}  // No change in step 3
        };
        
        run_test_case(&test);
    }
    
    // ------------------------------------------------------------------------
    // TEST 2: Step 3 Joining - match=3
    // ------------------------------------------------------------------------
    {
        const char* lines_a[] = {
            "// Header",
            "old line 1",
            "same line 1",
            "same line 2",
            "same line 3",
            "old line 2",
            "// Footer"
        };
        
        const char* lines_b[] = {
            "// Header",
            "new line 1",
            "same line 1",
            "same line 2",
            "same line 3",
            "new line 2",
            "// Footer"
        };
        
        ExpectedDiff myers_diffs[] = {
            {1, 2, 1, 2},
            {5, 6, 5, 6}
        };
        
        ExpectedDiff final_diffs[] = {
            {1, 6, 1, 6}  // Joined by step 3!
        };
        
        TestCase test = {
            .name = "Step 3 Remove Short - Two changes with 3-line match",
            .lines_a = lines_a,
            .len_a = 7,
            .lines_b = lines_b,
            .len_b = 7,
            .expected_myers = {myers_diffs, 2},
            .expected_optimize = {myers_diffs, 2},  // No change in step 2
            .expected_remove_short = {final_diffs, 1}
        };
        
        run_test_case(&test);
    }
    
    // ------------------------------------------------------------------------
    // TEST 3: No Optimization - contiguous changes
    // ------------------------------------------------------------------------
    {
        const char* lines_a[] = {
            "function test() {",
            "  old line 1",
            "  old line 2",
            "  old line 3",
            "}"
        };
        
        const char* lines_b[] = {
            "function test() {",
            "  new line 1",
            "  new line 2",
            "  new line 3",
            "}"
        };
        
        ExpectedDiff result_diffs[] = {
            {1, 4, 1, 4}
        };
        
        TestCase test = {
            .name = "No Optimization - Contiguous changes",
            .lines_a = lines_a,
            .len_a = 5,
            .lines_b = lines_b,
            .len_b = 5,
            .expected_myers = {result_diffs, 1},
            .expected_optimize = {result_diffs, 1},
            .expected_remove_short = {result_diffs, 1}
        };
        
        run_test_case(&test);
    }
    
    // ------------------------------------------------------------------------
    // TEST 4: Large Gap - no joining
    // ------------------------------------------------------------------------
    {
        const char* lines_a[] = {
            "// Section 1",
            "old line 1",
            "same 1",
            "same 2",
            "same 3",
            "same 4",
            "same 5",
            "old line 2",
            "// End"
        };
        
        const char* lines_b[] = {
            "// Section 1",
            "new line 1",
            "same 1",
            "same 2",
            "same 3",
            "same 4",
            "same 5",
            "new line 2",
            "// End"
        };
        
        ExpectedDiff result_diffs[] = {
            {1, 2, 1, 2},
            {7, 8, 7, 8}
        };
        
        TestCase test = {
            .name = "Large Gap - No joining (gap=5 > threshold)",
            .lines_a = lines_a,
            .len_a = 9,
            .lines_b = lines_b,
            .len_b = 9,
            .expected_myers = {result_diffs, 2},
            .expected_optimize = {result_diffs, 2},
            .expected_remove_short = {result_diffs, 2}
        };
        
        run_test_case(&test);
    }
    
    // ------------------------------------------------------------------------
    // SUMMARY
    // ------------------------------------------------------------------------
    printf("\n");
    printf("╔═══════════════════════════════════════════════════════════╗\n");
    printf("║              ALL PIPELINE TESTS PASSED ✓                  ║\n");
    printf("╚═══════════════════════════════════════════════════════════╝\n");
    printf("\n");
    printf("Pipeline Effectiveness Demonstrated:\n");
    printf("  • Step 1 (Myers):        Finds line-level diffs\n");
    printf("  • Step 2 (Optimize):     Joins diffs with gap ≤ 2\n");
    printf("  • Step 3 (Remove Short): Joins diffs with match ≤ 3\n");
    printf("\n");
    printf("Test Coverage:\n");
    printf("  ✓ Case 1: Step 2 joining (gap=2) - VERIFIED\n");
    printf("  ✓ Case 2: Step 3 joining (match=3) - VERIFIED\n");
    printf("  ✓ Case 3: No optimization needed - VERIFIED\n");
    printf("  ✓ Case 4: Large gap prevents joining - VERIFIED\n");
    printf("\n");
    printf("To add new test: Just define TestCase with lines + expectations!\n");
    printf("\n");
    
    return 0;
}
