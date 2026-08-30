// ============================================================================
// Diff Tool - Standalone executable for computing and displaying diffs
// ============================================================================
//
// Usage: diff_tool [-t] <original_file> <modified_file>
//
// Options:
//   -t    Show timing information for compute_diff
//
// This tool:
// 1. Reads two files from disk
// 2. Uses compute_diff() to compute their LinesDiff
// 3. Uses print_utils to print the results
//
// ============================================================================

#include "default_lines_diff_computer.h"
#include "print_utils.h"
#include "types.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdbool.h>

// ============================================================================
// Portable High-Resolution Timing
// ============================================================================

#ifdef _WIN32
#include <windows.h>

typedef struct {
    LARGE_INTEGER counter;
} portable_time_t;

static void portable_gettime(portable_time_t* t) {
    QueryPerformanceCounter(&t->counter);
}

static double portable_time_diff_ms(portable_time_t* start, portable_time_t* end) {
    static LARGE_INTEGER frequency = {0};
    if (frequency.QuadPart == 0) {
        QueryPerformanceFrequency(&frequency);
    }
    return (double)(end->counter.QuadPart - start->counter.QuadPart) / frequency.QuadPart * 1000.0;
}

#else
// POSIX (Linux, macOS)
typedef struct timespec portable_time_t;

static void portable_gettime(portable_time_t* t) {
    clock_gettime(CLOCK_MONOTONIC, t);
}

static double portable_time_diff_ms(portable_time_t* start, portable_time_t* end) {
    return (end->tv_sec - start->tv_sec) * 1000.0 + 
           (end->tv_nsec - start->tv_nsec) / 1000000.0;
}
#endif

// ============================================================================
// File Reading Utilities
// ============================================================================

/**
 * Read lines from a file into a dynamically allocated array.
 * Returns the number of lines read, or -1 on error.
 * 
 * IMPORTANT: Matches JavaScript's split('\n') behavior:
 *   - "a\nb\nc".split('\n') -> ["a", "b", "c"] (3 lines)
 *   - "a\nb\nc\n".split('\n') -> ["a", "b", "c", ""] (4 lines with trailing empty)
 *   - Keeps '\r' if present (doesn't strip it like fgets does)
 */
static int read_file_lines(const char* filename, char*** lines_out) {
    FILE* file = fopen(filename, "rb");
    if (!file) {
        fprintf(stderr, "Error: Cannot open file '%s'\n", filename);
        return -1;
    }
    
    // Read entire file content
    fseek(file, 0, SEEK_END);
    long file_size = ftell(file);
    fseek(file, 0, SEEK_SET);
    
    char* content = (char*)malloc(file_size + 1);
    if (!content) {
        fclose(file);
        return -1;
    }
    
    size_t bytes_read = fread(content, 1, file_size, file);
    content[bytes_read] = '\0';
    fclose(file);
    
    // Count lines by counting '\n' characters (matching JavaScript split('\n'))
    // This matches: "a\nb\nc".split('\n') -> ["a", "b", "c"] (3 lines)
    //               "a\nb\nc\n".split('\n') -> ["a", "b", "c", ""] (4 lines)
    int line_count = 1;  // At least one line (even empty file has 1 empty line)
    for (size_t i = 0; i < bytes_read; i++) {
        if (content[i] == '\n') {
            line_count++;
        }
    }
    
    // Allocate lines array
    char** lines = (char**)malloc(line_count * sizeof(char*));
    if (!lines) {
        free(content);
        return -1;
    }
    
    // Split by '\n' only, keeping '\r' if present (matching JavaScript behavior)
    // JavaScript: "line1\r\nline2\r\n".split('\n') -> ["line1\r", "line2\r", ""]
    int line_idx = 0;
    size_t line_start = 0;
    
    for (size_t i = 0; i <= bytes_read; i++) {
        if (i == bytes_read || content[i] == '\n') {
            // Extract line: everything from line_start to current position (excluding '\n')
            size_t line_len = i - line_start;
            
            lines[line_idx] = (char*)malloc(line_len + 1);
            if (!lines[line_idx]) {
                for (int j = 0; j < line_idx; j++) {
                    free(lines[j]);
                }
                free(lines);
                free(content);
                return -1;
            }
            
            memcpy(lines[line_idx], content + line_start, line_len);
            lines[line_idx][line_len] = '\0';
            line_idx++;
            line_start = i + 1;
        }
    }
    
    free(content);
    *lines_out = lines;
    return line_count;
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
    // Parse arguments
    bool show_timing = false;
    int timeout_ms = 5000; // Default timeout: 5 seconds
    int arg_idx = 1;

    // Parse optional flags
    while (arg_idx < argc && argv[arg_idx][0] == '-') {
        if (strcmp(argv[arg_idx], "--version") == 0 || strcmp(argv[arg_idx], "-v") == 0) {
            printf("vscode-diff %s\n", get_version());
            return 0;
        } else if (strcmp(argv[arg_idx], "-b") == 0) {
            show_timing = true;
            arg_idx++;
        } else if (strcmp(argv[arg_idx], "-T") == 0 || strcmp(argv[arg_idx], "--timeout") == 0) {
            if (arg_idx + 1 >= argc) {
                fprintf(stderr, "Error: %s requires a value\n", argv[arg_idx]);
                fprintf(stderr, "Usage: %s [-b] [-T <ms>] <original_file> <modified_file>\n", argv[0]);
                return 1;
            }
            timeout_ms = atoi(argv[arg_idx + 1]);
            if (timeout_ms < 0) {
                fprintf(stderr, "Error: Timeout must be non-negative\n");
                return 1;
            }
            arg_idx += 2;
        } else {
            fprintf(stderr, "Error: Unknown option: %s\n", argv[arg_idx]);
            fprintf(stderr, "Usage: %s [options] <original_file> <modified_file>\n", argv[0]);
            fprintf(stderr, "Try '%s --version' for version information\n", argv[0]);
            return 1;
        }
    }

    // Check for required file arguments
    if (argc - arg_idx != 2) {
        fprintf(stderr, "Usage: %s [options] <original_file> <modified_file>\n", argv[0]);
        fprintf(stderr, "Options:\n");
        fprintf(stderr, "  -v, --version   Show version information\n");
        fprintf(stderr, "  -b              Show benchmark timing information\n");
        fprintf(stderr, "  -T <ms>         Set timeout in milliseconds (default: 5000, 0 = no timeout)\n");
        fprintf(stderr, "  --timeout <ms>  Same as -T\n");
        return 1;
    }

    const char* original_file = argv[arg_idx];
    const char* modified_file = argv[arg_idx + 1];
    
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
        .max_computation_time_ms = timeout_ms,
        .compute_moves = true,
        .extend_to_subwords = false,
        .line_matcher_strategy = LINE_MATCHER_VSCODE,
        .line_matcher_threshold = 0.75
    };

    // Compute diff with timing
    portable_time_t start_time, end_time;
    clock_t cpu_start, cpu_end;
    
    portable_gettime(&start_time);
    cpu_start = clock();
    LinesDiff* diff = compute_diff(
        (const char**)original_lines,
        original_count,
        (const char**)modified_lines,
        modified_count,
        &options
    );
    cpu_end = clock();
    portable_gettime(&end_time);
    
    double wall_clock_ms = portable_time_diff_ms(&start_time, &end_time);
    double cpu_time_ms = ((double)(cpu_end - cpu_start)) / CLOCKS_PER_SEC * 1000.0;
    
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

    // Print moves
    printf("\n");
    if (diff->moves.count > 0) {
        printf("  Moves: %d move(s)\n", diff->moves.count);
        for (int i = 0; i < diff->moves.count; i++) {
            MovedText* m = &diff->moves.moves[i];
            printf("    [%d] Lines %d-%d -> Lines %d-%d\n", i,
                m->original.start_line, m->original.end_line - 1,
                m->modified.start_line, m->modified.end_line - 1);
        }
    } else {
        printf("  Moves: 0 move(s)\n");
    }

    printf("\n=================================================================\n");
    
    if (show_timing) {
        printf("Wall-clock time: %.3f ms (actual time elapsed)\n", wall_clock_ms);
        printf("CPU time:        %.3f ms (sum of all threads)\n", cpu_time_ms);
        if (cpu_time_ms > wall_clock_ms * 1.2) {
            double parallelism = cpu_time_ms / wall_clock_ms;
            printf("Parallelism:     %.2fx (using ~%.1f cores)\n", parallelism, parallelism);
        }
    }
    
    // Cleanup
    free_lines_diff(diff);
    free_lines(original_lines, original_count);
    free_lines(modified_lines, modified_count);
    
    return 0;
}
