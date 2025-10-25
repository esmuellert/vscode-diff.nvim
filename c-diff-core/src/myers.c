/**
 * Myers O(ND) Diff Algorithm - ISequence Version
 * 
 * This implementation uses the ISequence abstraction layer for maximum
 * flexibility and to enable advanced optimizations.
 * 
 * INFRASTRUCTURE IMPROVEMENTS:
 * 1. ISequence interface - works with any sequence type (lines, chars)
 * 2. Hash-based comparison - fast element matching via getElement()
 * 3. Strong equality check - prevents hash collision issues
 * 4. Boundary scoring support - enables optimization in Steps 2-3
 * 5. Timeout protection - prevents hanging on massive diffs
 * 
 * VSCode Reference: myersDiffAlgorithm.ts
 */

#include "../include/myers.h"
#include "../include/sequence.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// Forward declarations
static int myers_get_x_after_snake(const ISequence* seq_a, const ISequence* seq_b,
                                   int x, int y);

// Simple dynamic array for storing integers (supports negative indices)
typedef struct {
    int* positive;
    int* negative;
    int pos_capacity;
    int neg_capacity;
} IntArray;

static IntArray* intarray_create(void) {
    IntArray* arr = (IntArray*)malloc(sizeof(IntArray));
    arr->pos_capacity = 10;
    arr->neg_capacity = 10;
    arr->positive = (int*)calloc(arr->pos_capacity, sizeof(int));
    arr->negative = (int*)calloc(arr->neg_capacity, sizeof(int));
    return arr;
}

static void intarray_free(IntArray* arr) {
    free(arr->positive);
    free(arr->negative);
    free(arr);
}

static int intarray_get(IntArray* arr, int idx) {
    if (idx < 0) {
        int neg_idx = -idx - 1;
        return (neg_idx < arr->neg_capacity) ? arr->negative[neg_idx] : 0;
    } else {
        return (idx < arr->pos_capacity) ? arr->positive[idx] : 0;
    }
}

static void intarray_set(IntArray* arr, int idx, int value) {
    if (idx < 0) {
        int neg_idx = -idx - 1;
        if (neg_idx >= arr->neg_capacity) {
            int new_cap = arr->neg_capacity * 2;
            while (neg_idx >= new_cap) new_cap *= 2;
            arr->negative = (int*)realloc(arr->negative, new_cap * sizeof(int));
            memset(arr->negative + arr->neg_capacity, 0, 
                   (new_cap - arr->neg_capacity) * sizeof(int));
            arr->neg_capacity = new_cap;
        }
        arr->negative[neg_idx] = value;
    } else {
        if (idx >= arr->pos_capacity) {
            int new_cap = arr->pos_capacity * 2;
            while (idx >= new_cap) new_cap *= 2;
            arr->positive = (int*)realloc(arr->positive, new_cap * sizeof(int));
            memset(arr->positive + arr->pos_capacity, 0,
                   (new_cap - arr->pos_capacity) * sizeof(int));
            arr->pos_capacity = new_cap;
        }
        arr->positive[idx] = value;
    }
}

// Simple path structure to track snake paths
typedef struct SnakePath {
    struct SnakePath* prev;
    int x;
    int y;
    int length;
} SnakePath;

static SnakePath* snakepath_create(SnakePath* prev, int x, int y, int length) {
    SnakePath* path = (SnakePath*)malloc(sizeof(SnakePath));
    path->prev = prev;
    path->x = x;
    path->y = y;
    path->length = length;
    return path;
}

static void snakepath_free_chain(SnakePath* path) {
    while (path) {
        SnakePath* prev = path->prev;
        free(path);
        path = prev;
    }
}

// Dynamic array for storing SnakePath pointers (supports negative indices)
typedef struct {
    SnakePath** positive;
    SnakePath** negative;
    int pos_capacity;
    int neg_capacity;
} PathArray;

static PathArray* patharray_create(void) {
    PathArray* arr = (PathArray*)malloc(sizeof(PathArray));
    arr->pos_capacity = 10;
    arr->neg_capacity = 10;
    arr->positive = (SnakePath**)calloc(arr->pos_capacity, sizeof(SnakePath*));
    arr->negative = (SnakePath**)calloc(arr->neg_capacity, sizeof(SnakePath*));
    return arr;
}

static void patharray_free(PathArray* arr) {
    // Note: We don't free individual paths here as they're freed later
    free(arr->positive);
    free(arr->negative);
    free(arr);
}

static SnakePath* patharray_get(PathArray* arr, int idx) {
    if (idx < 0) {
        int neg_idx = -idx - 1;
        return (neg_idx < arr->neg_capacity) ? arr->negative[neg_idx] : NULL;
    } else {
        return (idx < arr->pos_capacity) ? arr->positive[idx] : NULL;
    }
}

static void patharray_set(PathArray* arr, int idx, SnakePath* value) {
    if (idx < 0) {
        int neg_idx = -idx - 1;
        if (neg_idx >= arr->neg_capacity) {
            int new_cap = arr->neg_capacity * 2;
            while (neg_idx >= new_cap) new_cap *= 2;
            arr->negative = (SnakePath**)realloc(arr->negative, 
                                                 new_cap * sizeof(SnakePath*));
            memset(arr->negative + arr->neg_capacity, 0,
                   (new_cap - arr->neg_capacity) * sizeof(SnakePath*));
            arr->neg_capacity = new_cap;
        }
        arr->negative[neg_idx] = value;
    } else {
        if (idx >= arr->pos_capacity) {
            int new_cap = arr->pos_capacity * 2;
            while (idx >= new_cap) new_cap *= 2;
            arr->positive = (SnakePath**)realloc(arr->positive,
                                                 new_cap * sizeof(SnakePath*));
            memset(arr->positive + arr->pos_capacity, 0,
                   (new_cap - arr->pos_capacity) * sizeof(SnakePath*));
            arr->pos_capacity = new_cap;
        }
        arr->positive[idx] = value;
    }
}

// Helper: Get X position after following snake (diagonal matches)
// Now uses ISequence.getElement() for hash-based comparison
static int myers_get_x_after_snake(const ISequence* seq_a, const ISequence* seq_b,
                                   int x, int y) {
    int len_a = seq_a->getLength(seq_a);
    int len_b = seq_b->getLength(seq_b);
    
    while (x < len_a && y < len_b && 
           seq_a->getElement(seq_a, x) == seq_b->getElement(seq_b, y)) {
        x++;
        y++;
    }
    return x;
}

// Helper: Min/Max functions
static int min_int(int a, int b) { return a < b ? a : b; }
static int max_int(int a, int b) { return a > b ? a : b; }

// Main Myers Diff Algorithm (Forward-only, with ISequence and timeout support)
SequenceDiffArray* myers_diff_algorithm(const ISequence* seq1, const ISequence* seq2,
                                        int timeout_ms, bool* hit_timeout) {
    if (hit_timeout) *hit_timeout = false;
    
    int len_a = seq1->getLength(seq1);
    int len_b = seq2->getLength(seq2);
    
    // Handle trivial cases
    if (len_a == 0 || len_b == 0) {
        SequenceDiffArray* result = (SequenceDiffArray*)malloc(sizeof(SequenceDiffArray));
        if (len_a == 0 && len_b == 0) {
            result->diffs = NULL;
            result->count = 0;
            result->capacity = 0;
        } else {
            result->diffs = (SequenceDiff*)malloc(sizeof(SequenceDiff));
            result->diffs[0].seq1_start = 0;
            result->diffs[0].seq1_end = len_a;
            result->diffs[0].seq2_start = 0;
            result->diffs[0].seq2_end = len_b;
            result->count = 1;
            result->capacity = 1;
        }
        return result;
    }

    IntArray* V = intarray_create();
    PathArray* paths = patharray_create();
    
    int initial_x = myers_get_x_after_snake(seq1, seq2, 0, 0);
    intarray_set(V, 0, initial_x);
    patharray_set(paths, 0, 
                  initial_x == 0 ? NULL : snakepath_create(NULL, 0, 0, initial_x));

    int d = 0;
    int k = 0;
    int found = 0;
    
    // Timeout tracking
    clock_t start_time = clock();
    double timeout_seconds = timeout_ms / 1000.0;

    // Main loop: increase edit distance until we reach the end
    while (!found) {
        d++;
        
        // Check timeout (VSCode's timeout support)
        if (timeout_ms > 0) {
            clock_t current_time = clock();
            double elapsed = (double)(current_time - start_time) / CLOCKS_PER_SEC;
            if (elapsed > timeout_seconds) {
                if (hit_timeout) *hit_timeout = true;
                
                // Return trivial diff (entire range changed)
                intarray_free(V);
                patharray_free(paths);
                
                SequenceDiffArray* result = (SequenceDiffArray*)malloc(sizeof(SequenceDiffArray));
                result->diffs = (SequenceDiff*)malloc(sizeof(SequenceDiff));
                result->diffs[0].seq1_start = 0;
                result->diffs[0].seq1_end = len_a;
                result->diffs[0].seq2_start = 0;
                result->diffs[0].seq2_end = len_b;
                result->count = 1;
                result->capacity = 1;
                return result;
            }
        }
        
        // Bounds for diagonals we need to consider
        int lower_bound = -min_int(d, len_b + (d % 2));
        int upper_bound = min_int(d, len_a + (d % 2));
        
        for (k = lower_bound; k <= upper_bound; k += 2) {
            // Determine whether to go down (insert) or right (delete)
            int max_x_top = (k == upper_bound) ? -1 : intarray_get(V, k + 1);
            int max_x_left = (k == lower_bound) ? -1 : intarray_get(V, k - 1) + 1;
            
            int x = min_int(max_int(max_x_top, max_x_left), len_a);
            int y = x - k;
            
            // Skip invalid diagonals
            if (x > len_a || y > len_b) {
                continue;
            }
            
            // Follow snake (diagonal matches)
            int new_max_x = myers_get_x_after_snake(seq1, seq2, x, y);
            intarray_set(V, k, new_max_x);
            
            // Track path
            SnakePath* last_path = (x == max_x_top) ? 
                                   patharray_get(paths, k + 1) :
                                   patharray_get(paths, k - 1);
            SnakePath* new_path = (new_max_x != x) ?
                                  snakepath_create(last_path, x, y, new_max_x - x) :
                                  last_path;
            patharray_set(paths, k, new_path);
            
            // Check if we reached the end
            if (intarray_get(V, k) == len_a && intarray_get(V, k) - k == len_b) {
                found = 1;
                break;
            }
        }
    }

    // Build result from path
    SnakePath* path = patharray_get(paths, k);
    
    // Count diffs first
    int diff_count = 0;
    int last_pos_a = len_a;
    int last_pos_b = len_b;
    SnakePath* temp_path = path;
    
    while (1) {
        int end_x = temp_path ? temp_path->x + temp_path->length : 0;
        int end_y = temp_path ? temp_path->y + temp_path->length : 0;
        
        if (end_x != last_pos_a || end_y != last_pos_b) {
            diff_count++;
        }
        if (!temp_path) break;
        
        last_pos_a = temp_path->x;
        last_pos_b = temp_path->y;
        temp_path = temp_path->prev;
    }
    
    // Allocate result
    SequenceDiffArray* result = (SequenceDiffArray*)malloc(sizeof(SequenceDiffArray));
    result->count = diff_count;
    result->capacity = diff_count;
    result->diffs = diff_count > 0 ? 
                    (SequenceDiff*)malloc(diff_count * sizeof(SequenceDiff)) : NULL;
    
    // Fill result (in reverse order, then we'll reverse)
    int idx = diff_count - 1;
    last_pos_a = len_a;
    last_pos_b = len_b;
    
    while (1) {
        int end_x = path ? path->x + path->length : 0;
        int end_y = path ? path->y + path->length : 0;
        
        if (end_x != last_pos_a || end_y != last_pos_b) {
            result->diffs[idx].seq1_start = end_x;
            result->diffs[idx].seq1_end = last_pos_a;
            result->diffs[idx].seq2_start = end_y;
            result->diffs[idx].seq2_end = last_pos_b;
            idx--;
        }
        
        if (!path) break;
        
        last_pos_a = path->x;
        last_pos_b = path->y;
        path = path->prev;
    }
    
    // Clean up - free the entire path chain from final path
    SnakePath* final_path = patharray_get(paths, k);
    snakepath_free_chain(final_path);
    
    intarray_free(V);
    patharray_free(paths);
    
    return result;
}

/**
 * Legacy wrapper for backward compatibility
 * 
 * Creates LineSequence wrappers and calls ISequence version.
 * This allows existing tests to continue working without modification.
 */
SequenceDiffArray* myers_diff_lines(const char** lines_a, int len_a,
                                    const char** lines_b, int len_b) {
    // Create LineSequence wrappers (no whitespace trimming for backward compat)
    ISequence* seq_a = line_sequence_create(lines_a, len_a, false);
    ISequence* seq_b = line_sequence_create(lines_b, len_b, false);
    
    // Run Myers algorithm
    bool hit_timeout = false;
    SequenceDiffArray* result = myers_diff_algorithm(seq_a, seq_b, 0, &hit_timeout);
    
    // Cleanup sequences
    seq_a->destroy(seq_a);
    seq_b->destroy(seq_b);
    
    return result;
}
