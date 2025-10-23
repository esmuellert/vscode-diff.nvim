#include <stdlib.h>
#include <string.h>
#include "../include/types.h"

// ============================================================================
// Myers Diff Algorithm - LCS-Based Implementation  
// VSCode Reference: src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/myersDiffAlgorithm.ts
// ============================================================================

// Forward declarations
extern void* mem_alloc(size_t size);
extern bool str_equal(const char* a, const char* b);
extern SequenceDiffArray* sequence_diff_array_create(void);
extern void sequence_diff_array_append(SequenceDiffArray* arr, SequenceDiff diff);

// LCS-based diff using dynamic programming
// This is simpler and more reliable for Step 1
SequenceDiffArray* myers_diff_compute(const char** lines_a, int count_a, 
                                      const char** lines_b, int count_b) {
    if (count_a < 0 || count_b < 0) {
        return NULL;
    }
    
    SequenceDiffArray* result = sequence_diff_array_create();
    
    if (count_a == 0 && count_b == 0) {
        return result;
    }
    
    if (!lines_a && count_a > 0) return result;
    if (!lines_b && count_b > 0) return result;
    
    if (count_a == 0) {
        SequenceDiff diff = { 0, 0, 0, count_b };
        sequence_diff_array_append(result, diff);
        return result;
    }
    
    if (count_b == 0) {
        SequenceDiff diff = { 0, count_a, 0, 0 };
        sequence_diff_array_append(result, diff);
        return result;
    }
    
    // Build LCS table
    int** lcs = (int**)mem_alloc((count_a + 1) * sizeof(int*));
    for (int i = 0; i <= count_a; i++) {
        lcs[i] = (int*)calloc(count_b + 1, sizeof(int));
    }
    
    for (int i = 1; i <= count_a; i++) {
        for (int j = 1; j <= count_b; j++) {
            if (str_equal(lines_a[i-1], lines_b[j-1])) {
                lcs[i][j] = lcs[i-1][j-1] + 1;
            } else {
                lcs[i][j] = lcs[i-1][j] > lcs[i][j-1] ? lcs[i-1][j] : lcs[i][j-1];
            }
        }
    }
    
    // Backtrack to find diff regions
    int i = count_a, j = count_b;
    int diff_end_a = -1, diff_end_b = -1;
    
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && str_equal(lines_a[i-1], lines_b[j-1])) {
            // Match found - end any ongoing diff
            if (diff_end_a >= 0 || diff_end_b >= 0) {
                SequenceDiff diff = {
                    i,  // Start at current position (after the match)
                    diff_end_a >= 0 ? diff_end_a : i,
                    j,
                    diff_end_b >= 0 ? diff_end_b : j
                };
                sequence_diff_array_append(result, diff);
                diff_end_a = -1;
                diff_end_b = -1;
            }
            i--;
            j--;
        } else if (j > 0 && (i == 0 || lcs[i][j-1] >= lcs[i-1][j])) {
            // Insertion in B
            if (diff_end_b < 0) diff_end_b = j;
            if (diff_end_a < 0) diff_end_a = i;
            j--;
        } else {
            // Deletion from A
            if (diff_end_a < 0) diff_end_a = i;
            if (diff_end_b < 0) diff_end_b = j;
            i--;
        }
    }
    
    // Add final diff if any
    if (diff_end_a >= 0 || diff_end_b >= 0) {
        SequenceDiff diff = {
            0,
            diff_end_a >= 0 ? diff_end_a : 0,
            0,
            diff_end_b >= 0 ? diff_end_b : 0
        };
        sequence_diff_array_append(result, diff);
    }
    
    // Reverse the result (we built it backwards)
    for (int k = 0; k < result->count / 2; k++) {
        SequenceDiff temp = result->diffs[k];
        result->diffs[k] = result->diffs[result->count - 1 - k];
        result->diffs[result->count - 1 - k] = temp;
    }
    
    // Free LCS table
    for (int i = 0; i <= count_a; i++) {
        free(lcs[i]);
    }
    free(lcs);
    
    return result;
}
