// ============================================================================
// Diff Tool - Standalone executable for computing and displaying diffs
// ============================================================================
//
// Usage: diff_tool <original_file> <modified_file>
//
// This tool:
// 1. Reads two files from disk
// 2. Uses compute_diff() to compute their LinesDiff
// 3. Uses print_utils to print the results
//
// ============================================================================

#include "include/default_lines_diff_computer.h"
#include "include/print_utils.h"
#include "include/types.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ============================================================================
// File Reading Utilities
// ============================================================================

/**
 * Read lines from a file into a dynamically allocated array.
 * Returns the number of lines read, or -1 on error.
 */
static int read_file_lines(const char* filename, char*** lines_out) {
    FILE* file = fopen(filename, "r");
    if (!file) {
        fprintf(stderr, "Error: Cannot open file '%s'\n", filename);
        return -1;
    }
    
    // Allocate initial capacity
    int capacity = 16;
    int count = 0;
    char** lines = (char**)malloc(capacity * sizeof(char*));
    if (!lines) {
        fclose(file);
        return -1;
    }
    
    // Read lines
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), file)) {
        // Remove newline if present
        size_t len = strlen(buffer);
        if (len > 0 && buffer[len - 1] == '\n') {
            buffer[len - 1] = '\0';
            len--;
        }
        
        // Expand capacity if needed
        if (count >= capacity) {
            capacity *= 2;
            char** new_lines = (char**)realloc(lines, capacity * sizeof(char*));
            if (!new_lines) {
                for (int i = 0; i < count; i++) {
                    free(lines[i]);
                }
                free(lines);
                fclose(file);
                return -1;
            }
            lines = new_lines;
        }
        
        // Duplicate the line
        lines[count] = strdup(buffer);
        if (!lines[count]) {
            for (int i = 0; i < count; i++) {
                free(lines[i]);
            }
            free(lines);
            fclose(file);
            return -1;
        }
        count++;
    }
    
    fclose(file);
    *lines_out = lines;
    return count;
}

/**
 * Free lines array.
 */
static void free_lines(char** lines, int count) {
    if (!lines) return;
    for (int i = 0; i < count; i++) {
        free(lines[i]);
    }
    free(lines);
}

// ============================================================================
// Main Program
// ============================================================================

int main(int argc, char* argv[]) {
    // Check arguments
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <original_file> <modified_file>\n", argv[0]);
        return 1;
    }
    
    const char* original_file = argv[1];
    const char* modified_file = argv[2];
    
    // Read original file
    char** original_lines = NULL;
    int original_count = read_file_lines(original_file, &original_lines);
    if (original_count < 0) {
        return 1;
    }
    
    // Read modified file
    char** modified_lines = NULL;
    int modified_count = read_file_lines(modified_file, &modified_lines);
    if (modified_count < 0) {
        free_lines(original_lines, original_count);
        return 1;
    }
    
    printf("=================================================================\n");
    printf("Diff Tool - Computing differences\n");
    printf("=================================================================\n");
    printf("Original: %s (%d lines)\n", original_file, original_count);
    printf("Modified: %s (%d lines)\n", modified_file, modified_count);
    printf("=================================================================\n\n");
    
    // Set up diff options
    DiffOptions options = {
        .ignore_trim_whitespace = false,
        .max_computation_time_ms = 0,  // No timeout
        .compute_moves = false,
        .extend_to_subwords = false
    };
    
    // Compute diff
    LinesDiff* diff = compute_diff(
        (const char**)original_lines,
        original_count,
        (const char**)modified_lines,
        modified_count,
        &options
    );
    
    if (!diff) {
        fprintf(stderr, "Error: Failed to compute diff\n");
        free_lines(original_lines, original_count);
        free_lines(modified_lines, modified_count);
        return 1;
    }
    
    // Print the results
    printf("Diff Results:\n");
    printf("=================================================================\n");
    printf("Number of changes: %d\n", diff->changes.count);
    printf("Hit timeout: %s\n", diff->hit_timeout ? "yes" : "no");
    printf("\n");
    
    if (diff->changes.count > 0) {
        print_detailed_line_range_mapping_array("Changes", &diff->changes);
    } else {
        printf("No differences found - files are identical.\n");
    }
    
    printf("\n=================================================================\n");
    
    // Cleanup
    free_lines_diff(diff);
    free_lines(original_lines, original_count);
    free_lines(modified_lines, modified_count);
    
    return 0;
}
