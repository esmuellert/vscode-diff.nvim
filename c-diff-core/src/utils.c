#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "../include/types.h"

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
