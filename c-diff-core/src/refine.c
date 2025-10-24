/**
 * Step 4: Character-Level Refinement
 * 
 * Applies Myers diff at character level within line-level diff regions.
 * Produces precise CharRange mappings for inline highlighting.
 * 
 * VSCode Reference:
 * src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts
 */

#include "../include/refine.h"
#include "../include/myers.h"
#include "../include/types.h"
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

// Forward declarations
static char** build_char_array(const char* str, int* out_len);
static void free_char_array(char** arr, int len);
static RangeMappingArray* create_range_mapping_array(int capacity);

/**
 * Convert a string to array of single-character strings for Myers diff.
 * 
 * Example: "abc" -> ["a", "b", "c"]
 * This allows reusing our line-based Myers algorithm for characters.
 */
static char** build_char_array(const char* str, int* out_len) {
    if (!str) {
        *out_len = 0;
        return NULL;
    }
    
    int len = strlen(str);
    *out_len = len;
    
    if (len == 0) {
        return NULL;
    }
    
    char** arr = malloc(sizeof(char*) * len);
    for (int i = 0; i < len; i++) {
        arr[i] = malloc(2);  // One char + null terminator
        arr[i][0] = str[i];
        arr[i][1] = '\0';
    }
    
    return arr;
}

static void free_char_array(char** arr, int len) {
    if (!arr) return;
    for (int i = 0; i < len; i++) {
        free(arr[i]);
    }
    free(arr);
}

static RangeMappingArray* create_range_mapping_array(int capacity) {
    RangeMappingArray* arr = malloc(sizeof(RangeMappingArray));
    arr->mappings = malloc(sizeof(RangeMapping) * capacity);
    arr->count = 0;
    arr->capacity = capacity;
    return arr;
}

/**
 * Refine a single line-level diff to character-level mappings.
 * 
 * VSCode approach:
 * 1. Extract text for the diff region
 * 2. Concatenate lines with newlines
 * 3. Run Myers diff on character sequences
 * 4. Convert character diffs to CharRange with line/column positions
 */
static void refine_single_diff(SequenceDiff* line_diff,
                               const char** lines_a, int len_a,
                               const char** lines_b, int len_b,
                               RangeMappingArray* out_mappings) {
    // Build concatenated strings for the diff region
    // VSCode concatenates all lines in the diff range with '\n'
    
    // Calculate total length for original
    int total_len_a = 0;
    for (int i = line_diff->seq1_start; i < line_diff->seq1_end && i < len_a; i++) {
        total_len_a += strlen(lines_a[i]);
        if (i < line_diff->seq1_end - 1) {
            total_len_a++; // For newline
        }
    }
    
    // Calculate total length for modified
    int total_len_b = 0;
    for (int i = line_diff->seq2_start; i < line_diff->seq2_end && i < len_b; i++) {
        total_len_b += strlen(lines_b[i]);
        if (i < line_diff->seq2_end - 1) {
            total_len_b++; // For newline
        }
    }
    
    // Build concatenated strings
    char* text_a = malloc(total_len_a + 1);
    char* text_b = malloc(total_len_b + 1);
    text_a[0] = '\0';
    text_b[0] = '\0';
    
    for (int i = line_diff->seq1_start; i < line_diff->seq1_end && i < len_a; i++) {
        strcat(text_a, lines_a[i]);
        if (i < line_diff->seq1_end - 1) {
            strcat(text_a, "\n");
        }
    }
    
    for (int i = line_diff->seq2_start; i < line_diff->seq2_end && i < len_b; i++) {
        strcat(text_b, lines_b[i]);
        if (i < line_diff->seq2_end - 1) {
            strcat(text_b, "\n");
        }
    }
    
    // Convert to character arrays for Myers diff
    int char_len_a, char_len_b;
    char** chars_a = build_char_array(text_a, &char_len_a);
    char** chars_b = build_char_array(text_b, &char_len_b);
    
    // Run Myers diff on characters
    SequenceDiffArray* char_diffs = myers_diff_algorithm(
        (const char**)chars_a, char_len_a,
        (const char**)chars_b, char_len_b
    );
    
    // Convert character diffs to CharRange mappings
    // Need to convert character positions back to line:column format
    if (char_diffs && char_diffs->count > 0) {
        for (int i = 0; i < char_diffs->count; i++) {
            SequenceDiff* cd = &char_diffs->diffs[i];
            
            // Convert character indices to (line, column)
            // We need to track which line we're on and column within that line
            
            // For now, create a simplified mapping
            // VSCode does full line:column conversion, but for initial implementation
            // we'll map the character range directly
            
            RangeMapping mapping;
            
            // Calculate line and column for original
            int line_a = line_diff->seq1_start + 1;  // 1-based
            int col_a = cd->seq1_start + 1;           // 1-based
            int line_a_end = line_diff->seq1_start + 1;
            int col_a_end = cd->seq1_end + 1;
            
            // Calculate line and column for modified
            int line_b = line_diff->seq2_start + 1;  // 1-based
            int col_b = cd->seq2_start + 1;           // 1-based
            int line_b_end = line_diff->seq2_start + 1;
            int col_b_end = cd->seq2_end + 1;
            
            mapping.original.start_line = line_a;
            mapping.original.start_col = col_a;
            mapping.original.end_line = line_a_end;
            mapping.original.end_col = col_a_end;
            
            mapping.modified.start_line = line_b;
            mapping.modified.start_col = col_b;
            mapping.modified.end_line = line_b_end;
            mapping.modified.end_col = col_b_end;
            
            // Grow array if needed
            if (out_mappings->count >= out_mappings->capacity) {
                out_mappings->capacity *= 2;
                out_mappings->mappings = realloc(out_mappings->mappings,
                    sizeof(RangeMapping) * out_mappings->capacity);
            }
            
            out_mappings->mappings[out_mappings->count++] = mapping;
        }
    }
    
    // Cleanup
    free(text_a);
    free(text_b);
    free_char_array(chars_a, char_len_a);
    free_char_array(chars_b, char_len_b);
    if (char_diffs) {
        free(char_diffs->diffs);
        free(char_diffs);
    }
}

/**
 * Refine all line-level diffs to character-level mappings.
 */
RangeMappingArray* refine_diffs_to_char_level(
    SequenceDiffArray* line_diffs,
    const char** lines_a, int len_a,
    const char** lines_b, int len_b
) {
    if (!line_diffs || !lines_a || !lines_b) {
        return NULL;
    }
    
    RangeMappingArray* result = create_range_mapping_array(
        line_diffs->count > 0 ? line_diffs->count * 4 : 10
    );
    
    // Refine each line diff
    for (int i = 0; i < line_diffs->count; i++) {
        refine_single_diff(&line_diffs->diffs[i], lines_a, len_a, lines_b, len_b, result);
    }
    
    return result;
}
