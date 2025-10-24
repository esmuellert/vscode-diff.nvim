/**
 * Step 2 & 3: Diff Optimization
 * 
 * Implements VSCode's diff optimization algorithms:
 * - Step 2: Shift boundaries to natural breakpoints, join adjacent diffs
 * - Step 3: Remove very short matches between diffs
 * 
 * VSCode Reference:
 * src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/diffAlgorithm.ts
 */

#include "../include/optimize.h"
#include "../include/types.h"
#include <string.h>
#include <ctype.h>
#include <stdbool.h>
#include <stdlib.h>

// Forward declarations for helper functions
static bool is_whitespace_only(const char* line);
static bool should_prefer_boundary(const char* line);
static bool shift_diff_boundary(SequenceDiff* diff,
                                const char** lines_a, int len_a,
                                const char** lines_b, int len_b);

/**
 * Check if a line contains only whitespace
 */
static bool is_whitespace_only(const char* line) {
    if (!line) return true;
    
    while (*line) {
        if (!isspace((unsigned char)*line)) {
            return false;
        }
        line++;
    }
    return true;
}

/**
 * Check if a line is a preferred boundary (blank, brace, etc.)
 * VSCode prefers boundaries at:
 * - Empty/whitespace lines
 * - Lines with only braces/brackets
 * - Lines with less indentation (dedent points)
 */
static bool should_prefer_boundary(const char* line) {
    if (!line) return true;
    
    // Whitespace-only lines are preferred
    if (is_whitespace_only(line)) {
        return true;
    }
    
    // Skip leading whitespace
    while (*line && isspace((unsigned char)*line)) {
        line++;
    }
    
    // Check for structural characters (braces, brackets)
    if (*line == '{' || *line == '}' || 
        *line == '[' || *line == ']' ||
        *line == '(' || *line == ')') {
        // Check if rest is whitespace
        line++;
        while (*line && isspace((unsigned char)*line)) {
            line++;
        }
        return *line == '\0';
    }
    
    return false;
}



/**
 * Shift diff boundaries to more natural positions
 * 
 * VSCode's algorithm:
 * 1. Try to shift diff start forward to a better boundary
 * 2. Try to shift diff end backward to a better boundary
 * 3. Prefer blank lines and structural boundaries
 */
static bool shift_diff_boundary(SequenceDiff* diff,
                                const char** lines_a, int len_a,
                                const char** lines_b, int len_b) {
    bool changed = false;
    
    // Shift start forward if possible
    // Look for a better boundary line within the diff
    int best_start_a = diff->seq1_start;
    int best_start_b = diff->seq2_start;
    
    // Only shift if both sequences have content to examine
    if (diff->seq1_start < diff->seq1_end && diff->seq2_start < diff->seq2_end) {
        // Look for blank lines or structural boundaries within the diff
        int max_shift = (diff->seq1_end - diff->seq1_start) < (diff->seq2_end - diff->seq2_start) ?
                       (diff->seq1_end - diff->seq1_start) : (diff->seq2_end - diff->seq2_start);
        
        for (int i = 0; i < max_shift; i++) {
            int idx_a = diff->seq1_start + i;
            int idx_b = diff->seq2_start + i;
            
            if (idx_a < len_a && idx_b < len_b) {
                // Check if this is a preferred boundary in BOTH sequences
                bool prefer_a = should_prefer_boundary(lines_a[idx_a]);
                bool prefer_b = should_prefer_boundary(lines_b[idx_b]);
                
                if (prefer_a && prefer_b) {
                    best_start_a = idx_a;
                    best_start_b = idx_b;
                }
            }
        }
    }
    
    // Apply shift if found a better boundary
    if (best_start_a != diff->seq1_start || best_start_b != diff->seq2_start) {
        diff->seq1_start = best_start_a;
        diff->seq2_start = best_start_b;
        changed = true;
    }
    
    // Shift end backward similarly (try to end at a clean boundary)
    int best_end_a = diff->seq1_end;
    int best_end_b = diff->seq2_end;
    
    // Look backward from the end
    if (diff->seq1_end > diff->seq1_start && diff->seq2_end > diff->seq2_start) {
        int max_shift_back = (diff->seq1_end - diff->seq1_start) < (diff->seq2_end - diff->seq2_start) ?
                             (diff->seq1_end - diff->seq1_start) : (diff->seq2_end - diff->seq2_start);
        
        for (int i = 1; i <= max_shift_back; i++) {
            int idx_a = diff->seq1_end - i;
            int idx_b = diff->seq2_end - i;
            
            if (idx_a >= 0 && idx_a < len_a && idx_b >= 0 && idx_b < len_b) {
                bool prefer_a = should_prefer_boundary(lines_a[idx_a]);
                bool prefer_b = should_prefer_boundary(lines_b[idx_b]);
                
                if (prefer_a && prefer_b) {
                    best_end_a = idx_a + 1;  // +1 because end is exclusive
                    best_end_b = idx_b + 1;
                }
            }
        }
    }
    
    // Apply backward shift if found a better boundary
    if (best_end_a != diff->seq1_end || best_end_b != diff->seq2_end) {
        diff->seq1_end = best_end_a;
        diff->seq2_end = best_end_b;
        changed = true;
    }
    
    return changed;
}

/**
 * Step 2: Optimize sequence diffs
 * 
 * VSCode's algorithm (from diffAlgorithm.ts):
 * 1. Shift each diff boundary to preferred positions
 * 2. Join diffs that are very close together
 */
bool optimize_sequence_diffs(SequenceDiffArray* diffs,
                             const char** lines_a, int len_a,
                             const char** lines_b, int len_b) {
    if (!diffs || !lines_a || !lines_b) {
        return false;
    }
    
    // Empty diff array is valid
    if (diffs->count == 0) {
        return true;
    }
    
    // Step 1: Shift boundaries for each diff
    for (int i = 0; i < diffs->count; i++) {
        shift_diff_boundary(&diffs->diffs[i], lines_a, len_a, lines_b, len_b);
    }
    
    // Step 2: Join adjacent diffs if they're very close
    // VSCode joins diffs with gaps of 1-2 lines
    int write_idx = 0;
    for (int read_idx = 0; read_idx < diffs->count; read_idx++) {
        if (write_idx == 0) {
            // First diff, just copy it
            if (read_idx != write_idx) {
                diffs->diffs[write_idx] = diffs->diffs[read_idx];
            }
            write_idx++;
        } else {
            // Check if we should join with previous diff
            SequenceDiff* prev = &diffs->diffs[write_idx - 1];
            SequenceDiff* curr = &diffs->diffs[read_idx];
            
            // Calculate gap between diffs
            int gap_a = curr->seq1_start - prev->seq1_end;
            int gap_b = curr->seq2_start - prev->seq2_end;
            
            // VSCode joins if gap <= 2 in either sequence
            if (gap_a <= 2 && gap_b <= 2 && gap_a >= 0 && gap_b >= 0) {
                // Join by extending previous diff
                prev->seq1_end = curr->seq1_end;
                prev->seq2_end = curr->seq2_end;
                // Don't increment write_idx, we're merging
            } else {
                // Keep as separate diff
                if (read_idx != write_idx) {
                    diffs->diffs[write_idx] = diffs->diffs[read_idx];
                }
                write_idx++;
            }
        }
    }
    
    // Update count after joining
    diffs->count = write_idx;
    
    return true;
}

/**
 * Step 3: Remove very short matches
 * 
 * VSCode's algorithm (from diffAlgorithm.ts - removeShortMatches):
 * If there's a short matching region between two diffs, join them into one larger diff.
 * 
 * Example:
 *   Before: [diff1: 0-5] [match: 5-6] [diff2: 6-10]
 *   After:  [diff_merged: 0-10]
 */
bool remove_short_matches(SequenceDiffArray* diffs,
                         const char** lines_a __attribute__((unused)), 
                         int len_a __attribute__((unused)),
                         const char** lines_b __attribute__((unused)), 
                         int len_b __attribute__((unused)),
                         int max_match_length) {
    if (!diffs || !lines_a || !lines_b) {
        return false;
    }
    
    // Empty or single diff array doesn't need processing
    if (diffs->count <= 1) {
        return true;
    }
    
    // Build new array by joining diffs separated by short matches
    int write_idx = 0;
    for (int read_idx = 0; read_idx < diffs->count; read_idx++) {
        if (write_idx == 0) {
            // First diff
            if (read_idx != write_idx) {
                diffs->diffs[write_idx] = diffs->diffs[read_idx];
            }
            write_idx++;
        } else {
            SequenceDiff* prev = &diffs->diffs[write_idx - 1];
            SequenceDiff* curr = &diffs->diffs[read_idx];
            
            // Calculate the match region between prev and curr
            int match_len_a = curr->seq1_start - prev->seq1_end;
            int match_len_b = curr->seq2_start - prev->seq2_end;
            
            // Check if both sequences have a match region
            // and both are short (below threshold)
            if (match_len_a >= 0 && match_len_b >= 0 &&
                match_len_a <= max_match_length && match_len_b <= max_match_length) {
                // Join diffs by extending previous to include current
                prev->seq1_end = curr->seq1_end;
                prev->seq2_end = curr->seq2_end;
                // Don't increment write_idx
            } else {
                // Keep as separate diff
                if (read_idx != write_idx) {
                    diffs->diffs[write_idx] = diffs->diffs[read_idx];
                }
                write_idx++;
            }
        }
    }
    
    // Update count
    diffs->count = write_idx;
    
    return true;
}
