#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <time.h>
#include "types.h"

#ifdef _WIN32
#include <windows.h>
#endif

// ============================================================================
// Unicode Whitespace Detection - 100% JavaScript /\s/ Parity
// ============================================================================

/**
 * Check if a Unicode code point is whitespace.
 * 
 * This matches JavaScript's /\s/ regex exactly, which includes:
 * 
 * ASCII whitespace:
 *   - Space (U+0020)
 *   - Tab (U+0009)
 *   - Line Feed (U+000A)
 *   - Vertical Tab (U+000B)
 *   - Form Feed (U+000C)
 *   - Carriage Return (U+000D)
 * 
 * Unicode whitespace:
 *   - No-break space (U+00A0)
 *   - Ogham space mark (U+1680)
 *   - En quad through hair space (U+2000-U+200A)
 *   - Line separator (U+2028)
 *   - Paragraph separator (U+2029)
 *   - Narrow no-break space (U+202F)
 *   - Medium mathematical space (U+205F)
 *   - Ideographic space (U+3000)
 * 
 * VSCode Reference: JavaScript /\s/g in removeVeryShortMatchingLinesBetweenDiffs
 * 
 * @param ch Unicode code point (can be UTF-8 decoded value or ASCII char)
 * @return true if ch is whitespace according to JavaScript /\s/
 */
bool is_unicode_whitespace(uint32_t ch) {
    // ASCII whitespace (most common, check first for performance)
    if (ch == 0x0020 ||  // Space
        ch == 0x0009 ||  // Tab
        ch == 0x000A ||  // Line Feed (LF)
        ch == 0x000B ||  // Vertical Tab
        ch == 0x000C ||  // Form Feed
        ch == 0x000D) {  // Carriage Return (CR)
        return true;
    }
    
    // Unicode whitespace characters
    if (ch == 0x00A0 ||  // No-break space
        ch == 0x1680 ||  // Ogham space mark
        ch == 0x2028 ||  // Line separator
        ch == 0x2029 ||  // Paragraph separator
        ch == 0x202F ||  // Narrow no-break space
        ch == 0x205F ||  // Medium mathematical space
        ch == 0x3000) {  // Ideographic space
        return true;
    }
    
    // Range: En quad through hair space (U+2000 - U+200A)
    if (ch >= 0x2000 && ch <= 0x200A) {
        return true;
    }
    
    return false;
}

// ============================================================================
// Utility Functions
// ============================================================================

// Safe memory allocation with error checking
void* mem_alloc(size_t size) {
    void* ptr = malloc(size);
    if (!ptr && size > 0) {
        fprintf(stderr, "Memory allocation failed: %zu bytes\n", size);
        exit(1);
    }
    return ptr;
}

// Safe memory reallocation
void* mem_realloc(void* ptr, size_t size) {
    void* new_ptr = realloc(ptr, size);
    if (!new_ptr && size > 0) {
        fprintf(stderr, "Memory reallocation failed: %zu bytes\n", size);
        exit(1);
    }
    return new_ptr;
}

// Safe string duplication
char* str_dup_safe(const char* str) {
    if (!str) return NULL;
    size_t len = strlen(str);
    char* dup = (char*)mem_alloc(len + 1);
    memcpy(dup, str, len + 1);
    return dup;
}

// Trim whitespace from both ends of a string (in-place, returns new length)
size_t line_trim(char* str) {
    if (!str) return 0;
    
    // Trim from start
    char* start = str;
    while (*start && (*start == ' ' || *start == '\t' || *start == '\r' || *start == '\n')) {
        start++;
    }
    
    // All whitespace?
    if (*start == '\0') {
        str[0] = '\0';
        return 0;
    }
    
    // Trim from end
    char* end = start + strlen(start) - 1;
    while (end > start && (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n')) {
        end--;
    }
    
    // Calculate new length and move if needed
    size_t new_len = end - start + 1;
    if (start != str) {
        memmove(str, start, new_len);
    }
    str[new_len] = '\0';
    
    return new_len;
}

// Compare two strings for equality
bool str_equal(const char* a, const char* b) {
    if (a == b) return true;
    if (!a || !b) return false;
    return strcmp(a, b) == 0;
}

/**
 * Trim whitespace from a string and return new allocated string.
 * 
 * @param str String to trim
 * @return Newly allocated trimmed string (caller must free)
 */
char* trim_string(const char* str) {
    if (!str) return NULL;
    
    // Find start (skip leading whitespace)
    const char* start = str;
    while (*start && (*start == ' ' || *start == '\t' || *start == '\r' || *start == '\n')) {
        start++;
    }
    
    // All whitespace?
    if (*start == '\0') {
        char* result = (char*)malloc(1);
        if (result) result[0] = '\0';
        return result;
    }
    
    // Find end (skip trailing whitespace)
    const char* end = start + strlen(start) - 1;
    while (end > start && (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n')) {
        end--;
    }
    
    // Allocate and copy
    size_t len = end - start + 1;
    char* result = (char*)malloc(len + 1);
    if (result) {
        memcpy(result, start, len);
        result[len] = '\0';
    }
    return result;
}

/**
 * Get current time in milliseconds.
 * 
 * @return Current time in milliseconds since epoch
 */
int64_t get_current_time_ms(void) {
    #ifdef _WIN32
        // Windows implementation
        return (int64_t)GetTickCount64();
    #else
        // POSIX implementation
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        return (int64_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
    #endif
}

// ============================================================================
// SequenceDiffArray Functions
// ============================================================================

SequenceDiffArray* sequence_diff_array_create(void) {
    SequenceDiffArray* arr = (SequenceDiffArray*)mem_alloc(sizeof(SequenceDiffArray));
    arr->diffs = NULL;
    arr->count = 0;
    arr->capacity = 0;
    return arr;
}

void sequence_diff_array_append(SequenceDiffArray* arr, SequenceDiff diff) {
    if (arr->count >= arr->capacity) {
        size_t new_capacity = arr->capacity == 0 ? 8 : arr->capacity * 2;
        arr->diffs = (SequenceDiff*)mem_realloc(arr->diffs, new_capacity * sizeof(SequenceDiff));
        arr->capacity = new_capacity;
    }
    arr->diffs[arr->count++] = diff;
}

void sequence_diff_array_free(SequenceDiffArray* arr) {
    if (!arr) return;
    free(arr->diffs);
    free(arr);
}

// ============================================================================
// RangeMappingArray Functions
// ============================================================================

RangeMappingArray* range_mapping_array_create(void) {
    RangeMappingArray* arr = (RangeMappingArray*)mem_alloc(sizeof(RangeMappingArray));
    arr->mappings = NULL;
    arr->count = 0;
    arr->capacity = 0;
    return arr;
}

void range_mapping_array_free(RangeMappingArray* arr) {
    if (!arr) return;
    free(arr->mappings);
    free(arr);
}

// ============================================================================
// DetailedLineRangeMappingArray Functions
// ============================================================================

DetailedLineRangeMappingArray* detailed_line_range_mapping_array_create(void) {
    DetailedLineRangeMappingArray* arr = (DetailedLineRangeMappingArray*)mem_alloc(sizeof(DetailedLineRangeMappingArray));
    arr->mappings = NULL;
    arr->count = 0;
    arr->capacity = 0;
    return arr;
}

void detailed_line_range_mapping_array_free(DetailedLineRangeMappingArray* arr) {
    if (!arr) return;
    for (int i = 0; i < arr->count; i++) {
        free(arr->mappings[i].inner_changes);
    }
    free(arr->mappings);
    free(arr);
}
