/**
 * Step 4: Character-Level Refinement - FULL VSCODE PARITY
 * 
 * Implements VSCode's refineDiff() with complete optimization pipeline.
 * 
 * VSCode References:
 * - defaultLinesDiffComputer.ts: refineDiff() (main function)
 * - linesSliceCharSequence.ts: LinesSliceCharSequence class
 * - heuristicSequenceOptimizations.ts: extendDiffsToEntireWordIfAppropriate, 
 *   removeVeryShortMatchingTextBetweenLongDiffs
 */

#include "../include/char_level.h"
#include "../include/myers.h"
#include "../include/optimize.h"
#include "../include/sequence.h"
#include "../include/types.h"
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <limits.h>

// =============================================================================
// Helper Functions
// =============================================================================

static inline int min_int(int a, int b) { return a < b ? a : b; }
static inline int max_int(int a, int b) { return a > b ? a : b; }

static bool is_valid_line_number(int line_number, int line_count) {
    return line_number >= 1 && line_number <= line_count;
}

static bool line_range_is_empty(LineRange range) {
    return range.start_line >= range.end_line;
}

static int safe_line_length(const char** lines, int line_count, int line_number) {
    if (line_number < 1 || line_number > line_count) {
        return 0;
    }
    const char* line = lines[line_number - 1];
    return line ? (int)strlen(line) : 0;
}

static void normalize_position(int* line, int* column, const char** lines, int line_count) {
    if (!line || !column) {
        return;
    }

    if (line_count <= 0) {
        *line = 1;
        *column = 1;
        return;
    }

    if (*line < 1) {
        *line = 1;
        *column = 1;
        return;
    }

    if (*line > line_count) {
        *line = line_count;
        int len = safe_line_length(lines, line_count, *line);
        if (*column > len + 1) {
            *column = len + 1;
        }
        if (*column < 1) {
            *column = 1;
        }
        return;
    }

    int len = safe_line_length(lines, line_count, *line);
    if (*column > len + 1) {
        *column = len + 1;
    }
    if (*column < 1) {
        *column = 1;
    }
}

static RangeMapping line_range_mapping_to_range_mapping2(
    LineRange original,
    LineRange modified,
    const char** original_lines,
    int original_count,
    const char** modified_lines,
    int modified_count
) {
    RangeMapping mapping;
    memset(&mapping, 0, sizeof(RangeMapping));

    bool original_valid = is_valid_line_number(original.end_line, original_count);
    bool modified_valid = is_valid_line_number(modified.end_line, modified_count);

    if (original_valid && modified_valid) {
        mapping.original.start_line = original.start_line;
        mapping.original.start_col = 1;
        mapping.original.end_line = original.end_line;
        mapping.original.end_col = 1;

        mapping.modified.start_line = modified.start_line;
        mapping.modified.start_col = 1;
        mapping.modified.end_line = modified.end_line;
        mapping.modified.end_col = 1;
        return mapping;
    }

    bool original_empty = line_range_is_empty(original);
    bool modified_empty = line_range_is_empty(modified);

    if (!original_empty && !modified_empty) {
        int orig_start_line = original.start_line;
        int orig_end_line = original.end_line - 1;
        int orig_end_col = INT_MAX / 2;
        normalize_position(&orig_end_line, &orig_end_col, original_lines, original_count);

        int mod_start_line = modified.start_line;
        int mod_end_line = modified.end_line - 1;
        int mod_end_col = INT_MAX / 2;
        normalize_position(&mod_end_line, &mod_end_col, modified_lines, modified_count);

        mapping.original.start_line = orig_start_line;
        mapping.original.start_col = 1;
        mapping.original.end_line = orig_end_line;
        mapping.original.end_col = orig_end_col;

        mapping.modified.start_line = mod_start_line;
        mapping.modified.start_col = 1;
        mapping.modified.end_line = mod_end_line;
        mapping.modified.end_col = mod_end_col;
        return mapping;
    }

    if (original.start_line > 1 && modified.start_line > 1) {
        int orig_start_line = original.start_line - 1;
        int orig_start_col = INT_MAX / 2;
        normalize_position(&orig_start_line, &orig_start_col, original_lines, original_count);

        int orig_end_line = original.end_line - 1;
        int orig_end_col = INT_MAX / 2;
        normalize_position(&orig_end_line, &orig_end_col, original_lines, original_count);

        int mod_start_line = modified.start_line - 1;
        int mod_start_col = INT_MAX / 2;
        normalize_position(&mod_start_line, &mod_start_col, modified_lines, modified_count);

        int mod_end_line = modified.end_line - 1;
        int mod_end_col = INT_MAX / 2;
        normalize_position(&mod_end_line, &mod_end_col, modified_lines, modified_count);

        mapping.original.start_line = orig_start_line;
        mapping.original.start_col = orig_start_col;
        mapping.original.end_line = orig_end_line;
        mapping.original.end_col = orig_end_col;

        mapping.modified.start_line = mod_start_line;
        mapping.modified.start_col = mod_start_col;
        mapping.modified.end_line = mod_end_line;
        mapping.modified.end_col = mod_end_col;
        return mapping;
    }

    int orig_line = original.start_line;
    int orig_col = 1;
    normalize_position(&orig_line, &orig_col, original_lines, original_count);

    int mod_line = modified.start_line;
    int mod_col = 1;
    normalize_position(&mod_line, &mod_col, modified_lines, modified_count);

    mapping.original.start_line = orig_line;
    mapping.original.start_col = orig_col;
    mapping.original.end_line = orig_line;
    mapping.original.end_col = orig_col;

    mapping.modified.start_line = mod_line;
    mapping.modified.start_col = mod_col;
    mapping.modified.end_line = mod_line;
    mapping.modified.end_col = mod_col;
    return mapping;
}

/**
 * Create RangeMappingArray with initial capacity
 */
static RangeMappingArray* create_range_mapping_array(int capacity) {
    RangeMappingArray* arr = (RangeMappingArray*)malloc(sizeof(RangeMappingArray));
    if (!arr) return NULL;
    
    arr->mappings = (RangeMapping*)malloc(sizeof(RangeMapping) * capacity);
    if (!arr->mappings) {
        free(arr);
        return NULL;
    }
    
    arr->count = 0;
    arr->capacity = capacity;
    return arr;
}

/**
 * Grow RangeMappingArray capacity
 */
static bool grow_range_mapping_array(RangeMappingArray* arr) {
    int new_capacity = arr->capacity * 2;
    RangeMapping* new_mappings = (RangeMapping*)realloc(arr->mappings, 
                                                       sizeof(RangeMapping) * new_capacity);
    if (!new_mappings) return false;
    
    arr->mappings = new_mappings;
    arr->capacity = new_capacity;
    return true;
}

/**
 * Add mapping to array
 */
static bool add_range_mapping(RangeMappingArray* arr, const RangeMapping* mapping) {
    if (arr->count >= arr->capacity) {
        if (!grow_range_mapping_array(arr)) {
            return false;
        }
    }
    
    arr->mappings[arr->count++] = *mapping;
    return true;
}

// =============================================================================
// extendDiffsToEntireWordIfAppropriate() - VSCode Parity
// =============================================================================

/**
 * Helper structure for equal mappings (inverted diffs)
 */
typedef struct {
    int offset1;
    int offset2;
} OffsetPair;

/**
 * Invert diffs to get equal mappings - VSCode SequenceDiff.invert()
 */
static SequenceDiffArray* invert_diffs(const SequenceDiffArray* diffs, int length1, int length2) {
    SequenceDiffArray* result = (SequenceDiffArray*)malloc(sizeof(SequenceDiffArray));
    result->capacity = diffs->count + 2;
    result->diffs = (SequenceDiff*)malloc(sizeof(SequenceDiff) * result->capacity);
    result->count = 0;
    
    int prev_end1 = 0;
    int prev_end2 = 0;
    
    for (int i = 0; i < diffs->count; i++) {
        const SequenceDiff* d = &diffs->diffs[i];
        
        // Add equal range before this diff
        if (d->seq1_start > prev_end1 || d->seq2_start > prev_end2) {
            SequenceDiff equal = {
                .seq1_start = prev_end1,
                .seq1_end = d->seq1_start,
                .seq2_start = prev_end2,
                .seq2_end = d->seq2_start
            };
            result->diffs[result->count++] = equal;
        }
        
        prev_end1 = d->seq1_end;
        prev_end2 = d->seq2_end;
    }
    
    // Add final equal range
    if (prev_end1 < length1 || prev_end2 < length2) {
        SequenceDiff equal = {
            .seq1_start = prev_end1,
            .seq1_end = length1,
            .seq2_start = prev_end2,
            .seq2_end = length2
        };
        result->diffs[result->count++] = equal;
    }
    
    return result;
}

/**
 * Merge two sorted diff arrays - VSCode mergeSequenceDiffs()
 */
static SequenceDiffArray* merge_diffs(SequenceDiffArray* arr1, SequenceDiffArray* arr2) {
    SequenceDiffArray* result = (SequenceDiffArray*)malloc(sizeof(SequenceDiffArray));
    result->capacity = arr1->count + arr2->count;
    result->diffs = (SequenceDiff*)malloc(sizeof(SequenceDiff) * result->capacity);
    result->count = 0;
    
    int i1 = 0, i2 = 0;
    
    while (i1 < arr1->count || i2 < arr2->count) {
        SequenceDiff next;
        
        if (i1 < arr1->count && (i2 >= arr2->count || arr1->diffs[i1].seq1_start < arr2->diffs[i2].seq1_start)) {
            next = arr1->diffs[i1++];
        } else {
            next = arr2->diffs[i2++];
        }
        
        // Merge with previous if they overlap/touch
        if (result->count > 0 && result->diffs[result->count - 1].seq1_end >= next.seq1_start) {
            SequenceDiff* prev = &result->diffs[result->count - 1];
            prev->seq1_end = max_int(prev->seq1_end, next.seq1_end);
            prev->seq2_end = max_int(prev->seq2_end, next.seq2_end);
        } else {
            result->diffs[result->count++] = next;
        }
    }
    
    return result;
}

/**
 * Helper structure for scanning words
 */
typedef struct {
    const CharSequence* seq1;
    const CharSequence* seq2;
    bool use_subwords;
    bool force;
    int* last_offset1;
    int* last_offset2;
    SequenceDiffArray* additional;
} ScanWordContext;

/**
 * Helper: Scan word at given position
 * This function mirrors VSCode's scanWord behavior, including the critical
 * while loop that continues consuming and merging overlapping equal spans.
 * 
 * NOTE: This modifies the queue_pos to consume equal mappings from the shared queue,
 * matching VSCode's closure-based approach where scanWord modifies the same array.
 */
static void scan_word(ScanWordContext* ctx, int offset1, int offset2, 
                     SequenceDiffArray* all_equal_mappings, int* queue_start_pos,
                     const SequenceDiff* current_equal_mapping) {
    if (offset1 < *ctx->last_offset1 || offset2 < *ctx->last_offset2) {
        return;
    }
    
    int w1_start, w1_end, w2_start, w2_end;
    bool found1, found2;
    
    if (ctx->use_subwords) {
        found1 = char_sequence_find_subword_containing(ctx->seq1, offset1, &w1_start, &w1_end);
        found2 = char_sequence_find_subword_containing(ctx->seq2, offset2, &w2_start, &w2_end);
    } else {
        found1 = char_sequence_find_word_containing(ctx->seq1, offset1, &w1_start, &w1_end);
        found2 = char_sequence_find_word_containing(ctx->seq2, offset2, &w2_start, &w2_end);
    }
    
    if (!found1 || !found2) {
        return;
    }
    
    SequenceDiff word = {w1_start, w1_end, w2_start, w2_end};
    
    // Calculate equal part within word (intersection with current equal mapping)
    int equal_start1 = max_int(word.seq1_start, current_equal_mapping->seq1_start);
    int equal_end1 = min_int(word.seq1_end, current_equal_mapping->seq1_end);
    int equal_start2 = max_int(word.seq2_start, current_equal_mapping->seq2_start);
    int equal_end2 = min_int(word.seq2_end, current_equal_mapping->seq2_end);
    
    int equal_chars1 = max_int(0, equal_end1 - equal_start1);
    int equal_chars2 = max_int(0, equal_end2 - equal_start2);
    
    // VSCode critical feature: Keep consuming and merging overlapping equal spans
    // from the remaining queue (starting at queue_start_pos).
    // This is where we achieve parity with VSCode's while(equalMappings.length > 0) loop.
    while (*queue_start_pos < all_equal_mappings->count) {
        const SequenceDiff* next = &all_equal_mappings->diffs[*queue_start_pos];
        
        // Check if the next equal mapping intersects with our current word
        bool intersects = (next->seq1_start < word.seq1_end && next->seq1_end > word.seq1_start) ||
                         (next->seq2_start < word.seq2_end && next->seq2_end > word.seq2_start);
        
        if (!intersects) {
            break;
        }
        
        // Find the parent word for the next equal mapping's start position
        int v1_start, v1_end, v2_start, v2_end;
        bool v_found1, v_found2;
        
        if (ctx->use_subwords) {
            v_found1 = char_sequence_find_subword_containing(ctx->seq1, next->seq1_start, &v1_start, &v1_end);
            v_found2 = char_sequence_find_subword_containing(ctx->seq2, next->seq2_start, &v2_start, &v2_end);
        } else {
            v_found1 = char_sequence_find_word_containing(ctx->seq1, next->seq1_start, &v1_start, &v1_end);
            v_found2 = char_sequence_find_word_containing(ctx->seq2, next->seq2_start, &v2_start, &v2_end);
        }
        
        if (!v_found1 || !v_found2) {
            break;
        }
        
        SequenceDiff v = {v1_start, v1_end, v2_start, v2_end};
        
        // Calculate the equal part of this new word with the next equal mapping
        int v_equal_start1 = max_int(v.seq1_start, next->seq1_start);
        int v_equal_end1 = min_int(v.seq1_end, next->seq1_end);
        int v_equal_start2 = max_int(v.seq2_start, next->seq2_start);
        int v_equal_end2 = min_int(v.seq2_end, next->seq2_end);
        
        int v_equal_chars1 = max_int(0, v_equal_end1 - v_equal_start1);
        int v_equal_chars2 = max_int(0, v_equal_end2 - v_equal_start2);
        
        equal_chars1 += v_equal_chars1;
        equal_chars2 += v_equal_chars2;
        
        // Join the words: w = w.join(v)
        word.seq1_start = min_int(word.seq1_start, v.seq1_start);
        word.seq1_end = max_int(word.seq1_end, v.seq1_end);
        word.seq2_start = min_int(word.seq2_start, v.seq2_start);
        word.seq2_end = max_int(word.seq2_end, v.seq2_end);
        
        // If the word extends beyond the next equal mapping, consume it (shift)
        if (word.seq1_end >= next->seq1_end) {
            (*queue_start_pos)++;  // Consume this mapping from the queue
        } else {
            break;
        }
    }
    
    // Check if we should extend to include this word
    // VSCode: if (force && equalChars1 + equalChars2 < w.seq1Range.length + w.seq2Range.length || 
    //             equalChars1 + equalChars2 < (w.seq1Range.length + w.seq2Range.length) * 2 / 3)
    // Due to operator precedence, this is: (force && condition1) || condition2
    // CRITICAL: Use floating-point math to match JavaScript's behavior!
    int word_len = (word.seq1_end - word.seq1_start) + (word.seq2_end - word.seq2_start);
    int equal_len = equal_chars1 + equal_chars2;
    
    bool should_extend = (ctx->force && equal_len < word_len) || 
                        (equal_len < word_len * 2.0 / 3.0);
    
    if (should_extend) {
        if (ctx->additional->count >= ctx->additional->capacity) {
            ctx->additional->capacity *= 2;
            ctx->additional->diffs = (SequenceDiff*)realloc(ctx->additional->diffs, 
                                                      sizeof(SequenceDiff) * ctx->additional->capacity);
        }
        ctx->additional->diffs[ctx->additional->count++] = word;
    }
    
    *ctx->last_offset1 = word.seq1_end;
    *ctx->last_offset2 = word.seq2_end;
}

/**
 * Extend diffs to entire word boundaries if appropriate - VSCode Parity
 * 
 * This is the complex function from VSCode's heuristicSequenceOptimizations.ts
 */
static SequenceDiffArray* extend_diffs_to_entire_word(
    const CharSequence* seq1,
    const CharSequence* seq2,
    const SequenceDiffArray* diffs,
    bool use_subwords,
    bool force
) {
    SequenceDiffArray* equal_mappings = invert_diffs(diffs, seq1->length, seq2->length);
    SequenceDiffArray* additional = (SequenceDiffArray*)malloc(sizeof(SequenceDiffArray));
    additional->capacity = 100;
    additional->diffs = (SequenceDiff*)malloc(sizeof(SequenceDiff) * additional->capacity);
    additional->count = 0;
    
    int last_offset1 = 0;
    int last_offset2 = 0;
    
    // Set up context for scan_word
    ScanWordContext ctx = {
        .seq1 = seq1,
        .seq2 = seq2,
        .use_subwords = use_subwords,
        .force = force,
        .last_offset1 = &last_offset1,
        .last_offset2 = &last_offset2,
        .additional = additional
    };
    
    // VSCode uses: while (equalMappings.length > 0) { const next = equalMappings.shift()!; ... }
    // We simulate with a position that advances. The key is that scan_word can also
    // advance queue_pos (consuming mappings), matching VSCode's closure-based approach.
    int queue_pos = 0;
    while (queue_pos < equal_mappings->count) {
        const SequenceDiff current = equal_mappings->diffs[queue_pos];
        queue_pos++;  // Consume current mapping (like shift())
        
        if (current.seq1_start >= current.seq1_end) {
            continue;
        }
        
        // Scan at start of equal region
        // Pass queue_pos as the start of remaining items (what's left after shift)
        scan_word(&ctx, current.seq1_start, current.seq2_start, 
                 equal_mappings, &queue_pos, &current);
        
        // Scan at end of equal region (one char before end)
        // VSCode: next.getEndExclusives().delta(-1)
        if (current.seq1_end > current.seq1_start + 1) {
            scan_word(&ctx, current.seq1_end - 1, current.seq2_end - 1, 
                     equal_mappings, &queue_pos, &current);
        }
    }
    
    // Merge original diffs with additional word extensions
    SequenceDiffArray* merged = merge_diffs((SequenceDiffArray*)diffs, additional);
    
    // Cleanup
    free(equal_mappings->diffs);
    free(equal_mappings);
    free(additional->diffs);
    free(additional);
    
    return merged;
}

// =============================================================================
// removeVeryShortMatchingTextBetweenLongDiffs() - VSCode Parity
// =============================================================================

/**
 * Remove very short matching text between long diffs - VSCode Parity
 * 
 * Complex heuristic from VSCode's heuristicSequenceOptimizations.ts
 */
static SequenceDiffArray* remove_very_short_text(
    const CharSequence* seq1,
    const CharSequence* seq2,
    SequenceDiffArray* diffs
) {
    if (diffs->count == 0) {
        return diffs;
    }
    
    int counter = 0;
    bool should_repeat;
    
    do {
        should_repeat = false;
        SequenceDiff* result = (SequenceDiff*)malloc(sizeof(SequenceDiff) * diffs->capacity);
        int result_count = 0;
        
        result[result_count++] = diffs->diffs[0];
        
        for (int i = 1; i < diffs->count; i++) {
            SequenceDiff* last_result = &result[result_count - 1];
            SequenceDiff cur = diffs->diffs[i];
            
            // Calculate unchanged range
            int unchanged_start = last_result->seq1_end;
            int unchanged_end = cur.seq1_start;
            
            if (unchanged_start >= unchanged_end) {
                // No gap, merge
                last_result->seq1_end = cur.seq1_end;
                last_result->seq2_end = cur.seq2_end;
                should_repeat = true;
                continue;
            }
            
            // Check line count
            int unchanged_line_count = char_sequence_count_lines_in(seq1, unchanged_start, unchanged_end);
            if (unchanged_line_count > 5 || (unchanged_end - unchanged_start) > 500) {
                result[result_count++] = cur;
                continue;
            }
            
            // Get unchanged text and check length
            char* unchanged_text = char_sequence_get_text(seq1, unchanged_start, unchanged_end);
            if (!unchanged_text) {
                result[result_count++] = cur;
                continue;
            }
            
            // Trim and check
            char* trimmed = unchanged_text;
            while (*trimmed && isspace(*trimmed)) trimmed++;
            char* end = trimmed + strlen(trimmed) - 1;
            while (end > trimmed && isspace(*end)) *end-- = '\0';
            
            bool short_text = (strlen(trimmed) <= 20);
            
            // Count newlines
            int newline_count = 0;
            for (char* p = trimmed; *p; p++) {
                if (*p == '\n' || *p == '\r') newline_count++;
            }
            bool single_line = (newline_count <= 1);
            
            free(unchanged_text);
            
            if (!short_text || !single_line) {
                result[result_count++] = cur;
                continue;
            }
            
            // Calculate diff sizes using complex formula (VSCode's power formula)
            int before_line1 = char_sequence_count_lines_in(seq1, last_result->seq1_start, last_result->seq1_end);
            int before_len1 = last_result->seq1_end - last_result->seq1_start;
            int before_line2 = char_sequence_count_lines_in(seq2, last_result->seq2_start, last_result->seq2_end);
            int before_len2 = last_result->seq2_end - last_result->seq2_start;
            
            int after_line1 = char_sequence_count_lines_in(seq1, cur.seq1_start, cur.seq1_end);
            int after_len1 = cur.seq1_end - cur.seq1_start;
            int after_line2 = char_sequence_count_lines_in(seq2, cur.seq2_start, cur.seq2_end);
            int after_len2 = cur.seq2_end - cur.seq2_start;
            
            // VSCode's formula
            const int max = 2 * 40 + 50;
            #define CAP(v) (min_int((v), max))
            
            double before_score = pow(pow(CAP(before_line1 * 40 + before_len1), 1.5) + 
                                     pow(CAP(before_line2 * 40 + before_len2), 1.5), 1.5);
            double after_score = pow(pow(CAP(after_line1 * 40 + after_len1), 1.5) + 
                                    pow(CAP(after_line2 * 40 + after_len2), 1.5), 1.5);
            double threshold = pow(pow(max, 1.5), 1.5) * 1.3;
            
            #undef CAP
            
            if (before_score + after_score > threshold) {
                // Merge
                last_result->seq1_end = cur.seq1_end;
                last_result->seq2_end = cur.seq2_end;
                should_repeat = true;
            } else {
                result[result_count++] = cur;
            }
        }
        
        free(diffs->diffs);
        diffs->diffs = result;
        diffs->count = result_count;
        diffs->capacity = diffs->capacity;  // Keep same capacity
        
    } while (counter++ < 10 && should_repeat);
    
    // Second phase: Remove short prefixes/suffixes (VSCode's forEachWithNeighbors logic)
    SequenceDiff* new_diffs = (SequenceDiff*)malloc(sizeof(SequenceDiff) * (diffs->capacity + 10));
    int new_count = 0;
    
    for (int i = 0; i < diffs->count; i++) {
        const SequenceDiff* prev = (i > 0) ? &diffs->diffs[i - 1] : NULL;
        const SequenceDiff* cur = &diffs->diffs[i];
        const SequenceDiff* next = (i < diffs->count - 1) ? &diffs->diffs[i + 1] : NULL;
        
        SequenceDiff new_diff = *cur;
        
        // Helper: shouldMarkAsChanged - check if text should be included in diff
        int total_range_len = (cur->seq1_end - cur->seq1_start) + (cur->seq2_end - cur->seq2_start);
        bool is_large_diff = (total_range_len > 100);
        
        // Get full line range
        int full_start, full_end;
        char_sequence_extend_to_full_lines(seq1, cur->seq1_start, cur->seq1_end, &full_start, &full_end);
        
        // Check prefix
        if (full_start < cur->seq1_start && is_large_diff) {
            int text_len = cur->seq1_start - full_start;
            char* prefix = char_sequence_get_text(seq1, full_start, cur->seq1_start);
            if (prefix) {
                // Trim whitespace
                const char* start = prefix;
                const char* end = prefix + strlen(prefix) - 1;
                while (*start && isspace((unsigned char)*start)) start++;
                while (end > start && isspace((unsigned char)*end)) end--;

                int trimmed_len = (start > end) ? 0 : (int)(end - start + 1);
                bool should_include = (text_len > 0 && trimmed_len <= 3);

                if (should_include) {
                    int prefix_len = cur->seq1_start - full_start;
                    new_diff.seq1_start -= prefix_len;
                    new_diff.seq2_start -= prefix_len;
                }
                free(prefix);
            }
        }
        
        // Check suffix
        if (cur->seq1_end < full_end && is_large_diff) {
            int text_len = full_end - cur->seq1_end;
            char* suffix = char_sequence_get_text(seq1, cur->seq1_end, full_end);
            if (suffix) {
                // Trim whitespace
                const char* start = suffix;
                const char* end = suffix + strlen(suffix) - 1;
                while (*start && isspace((unsigned char)*start)) start++;
                while (end > start && isspace((unsigned char)*end)) end--;

                int trimmed_len = (start > end) ? 0 : (int)(end - start + 1);
                bool should_include = (text_len > 0 && trimmed_len <= 3);

                if (should_include) {
                    int suffix_len = full_end - cur->seq1_end;
                    new_diff.seq1_end += suffix_len;
                    new_diff.seq2_end += suffix_len;
                }
                free(suffix);
            }
        }
        
        // Constrain to available space (SequenceDiff.fromOffsetPairs)
        int avail_start1 = prev ? prev->seq1_end : 0;
        int avail_start2 = prev ? prev->seq2_end : 0;
        int avail_end1 = next ? next->seq1_start : seq1->length;
        int avail_end2 = next ? next->seq2_start : seq2->length;
        
        // Intersect with available space
        new_diff.seq1_start = max_int(new_diff.seq1_start, avail_start1);
        new_diff.seq1_end = min_int(new_diff.seq1_end, avail_end1);
        new_diff.seq2_start = max_int(new_diff.seq2_start, avail_start2);
        new_diff.seq2_end = min_int(new_diff.seq2_end, avail_end2);
        
        // Add to result, merging if touching previous
        if (new_count > 0) {
            SequenceDiff* last = &new_diffs[new_count - 1];
            if (last->seq1_end == new_diff.seq1_start && last->seq2_end == new_diff.seq2_start) {
                // Merge with previous
                last->seq1_end = new_diff.seq1_end;
                last->seq2_end = new_diff.seq2_end;
                continue;
            }
        }
        
        new_diffs[new_count++] = new_diff;
    }
    
    free(diffs->diffs);
    diffs->diffs = new_diffs;
    diffs->count = new_count;
    diffs->capacity = diffs->capacity + 10;
    
    return diffs;
}

// =============================================================================
// Main Step 4 Implementation - refineDiff()
// =============================================================================

/**
 * Translate SequenceDiff char offsets to RangeMapping with line:col positions
 */
static RangeMapping translate_diff_to_range(
    const CharSequence* seq1,
    const CharSequence* seq2,
    const SequenceDiff* diff,
    int base_line1,
    int base_line2
) {
    RangeMapping mapping;
    
    int line1_start, col1_start, line1_end, col1_end;
    int line2_start, col2_start, line2_end, col2_end;
    
    // VSCode: translateRange() uses 'right' for start, 'left' for end
    char_sequence_translate_range(seq1, diff->seq1_start, diff->seq1_end,
                                  &line1_start, &col1_start, &line1_end, &col1_end);
    char_sequence_translate_range(seq2, diff->seq2_start, diff->seq2_end,
                                  &line2_start, &col2_start, &line2_end, &col2_end);
    
    // Convert to 1-based and add base line offset
    mapping.original.start_line = base_line1 + line1_start + 1;
    mapping.original.start_col = col1_start + 1;
    mapping.original.end_line = base_line1 + line1_end + 1;
    mapping.original.end_col = col1_end + 1;
    
    mapping.modified.start_line = base_line2 + line2_start + 1;
    mapping.modified.start_col = col2_start + 1;
    mapping.modified.end_line = base_line2 + line2_end + 1;
    mapping.modified.end_col = col2_end + 1;
    
    return mapping;
}

/**
 * Main refinement function - VSCode's refineDiff() - FULL PARITY
 */
RangeMappingArray* refine_diff_char_level(
    const SequenceDiff* line_diff,
    const char** lines_a, int len_a,
    const char** lines_b, int len_b,
    const CharLevelOptions* options,
    bool* out_hit_timeout
) {
    // Initialize timeout flag
    if (out_hit_timeout) {
        *out_hit_timeout = false;
    }
    
    if (!line_diff || !lines_a || !lines_b || !options) {
        return NULL;
    }
    
    // Step 1: Map line diff to character ranges using VSCode's toRangeMapping2 logic
    LineRange original_line_range = {
        .start_line = line_diff->seq1_start + 1,
        .end_line = line_diff->seq1_end + 1
    };
    LineRange modified_line_range = {
        .start_line = line_diff->seq2_start + 1,
        .end_line = line_diff->seq2_end + 1
    };

    RangeMapping base_range = line_range_mapping_to_range_mapping2(
        original_line_range,
        modified_line_range,
        lines_a,
        len_a,
        lines_b,
        len_b
    );

    ISequence* seq1_iface = char_sequence_create_from_range(
        lines_a,
        len_a,
        &base_range.original,
        options->consider_whitespace_changes
    );
    ISequence* seq2_iface = char_sequence_create_from_range(
        lines_b,
        len_b,
        &base_range.modified,
        options->consider_whitespace_changes
    );

    if (!seq1_iface || !seq2_iface) {
        if (seq1_iface) seq1_iface->destroy(seq1_iface);
        if (seq2_iface) seq2_iface->destroy(seq2_iface);
        return NULL;
    }
    
    // Extract CharSequence from ISequence
    // (In our implementation, ISequence contains CharSequence as data)
    CharSequence* seq1 = (CharSequence*)seq1_iface->data;
    CharSequence* seq2 = (CharSequence*)seq2_iface->data;

    int base_line1 = base_range.original.start_line - 1;
    int base_line2 = base_range.modified.start_line - 1;
    
    // Step 2: Run Myers on characters
    // VSCode uses DP if length < 500, otherwise Myers O(ND)
    // We now have automatic selection based on size
    int len1 = seq1_iface->getLength(seq1_iface);
    int len2 = seq2_iface->getLength(seq2_iface);
    bool hit_timeout = false;
    SequenceDiffArray* diffs;
    
    if (len1 + len2 < 500) {
        // Use DP algorithm for small character sequences
        diffs = myers_dp_diff_algorithm(seq1_iface, seq2_iface, 0, &hit_timeout, NULL, NULL);
    } else {
        // Use O(ND) algorithm for large character sequences
        diffs = myers_nd_diff_algorithm(seq1_iface, seq2_iface, 0, &hit_timeout);
    }
    
    if (!diffs) {
        seq1_iface->destroy(seq1_iface);
        seq2_iface->destroy(seq2_iface);
        return NULL;
    }

    // Step 3: optimizeSequenceDiffs() - Reuse Step 2 optimization
    optimize_sequence_diffs(seq1_iface, seq2_iface, diffs);
    
    // Step 4: extendDiffsToEntireWordIfAppropriate() - Word boundaries
    SequenceDiffArray* extended = extend_diffs_to_entire_word(seq1, seq2, diffs, false, false);
    free(diffs->diffs);
    free(diffs);
    diffs = extended;
    
    // Step 5: extendDiffsToEntireWordIfAppropriate() for subwords (if enabled)
    if (options->extend_to_subwords) {
        extended = extend_diffs_to_entire_word(seq1, seq2, diffs, true, true);
        free(diffs->diffs);
        free(diffs);
        diffs = extended;
    }

    // Step 6: removeShortMatches() - Remove ≤2 char gaps
    remove_short_matches(seq1_iface, seq2_iface, diffs);

    // Step 7: removeVeryShortMatchingTextBetweenLongDiffs()
    remove_very_short_text(seq1, seq2, diffs);
    
    // Step 8: Translate to RangeMapping with (line, column) positions
    RangeMappingArray* result = create_range_mapping_array(diffs->count);
    if (!result) {
        free(diffs->diffs);
        free(diffs);
        seq1_iface->destroy(seq1_iface);
        seq2_iface->destroy(seq2_iface);
        return NULL;
    }
    
    for (int i = 0; i < diffs->count; i++) {
        RangeMapping mapping = translate_diff_to_range(
            seq1, seq2, &diffs->diffs[i],
            base_line1, base_line2
        );
        add_range_mapping(result, &mapping);
    }
    
    // Propagate timeout status (VSCode: return { mappings, hitTimeout })
    if (out_hit_timeout) {
        *out_hit_timeout = hit_timeout;
    }
    
    // Cleanup
    free(diffs->diffs);
    free(diffs);
    seq1_iface->destroy(seq1_iface);
    seq2_iface->destroy(seq2_iface);
    
    return result;
}

/**
 * Refine all line-level diffs - VSCode Parity
 */
RangeMappingArray* refine_all_diffs_char_level(
    const SequenceDiffArray* line_diffs,
    const char** lines_a, int len_a,
    const char** lines_b, int len_b,
    const CharLevelOptions* options,
    bool* out_hit_timeout
) {
    // Initialize timeout flag
    if (out_hit_timeout) {
        *out_hit_timeout = false;
    }
    
    if (!line_diffs || !lines_a || !lines_b || !options) {
        return NULL;
    }
    
    RangeMappingArray* result = create_range_mapping_array(
        line_diffs->count > 0 ? line_diffs->count * 4 : 10
    );
    
    // Track if any refinement hit timeout
    bool any_timeout = false;
    
    // Refine each line diff
    for (int i = 0; i < line_diffs->count; i++) {
        bool local_timeout = false;
        RangeMappingArray* char_mappings = refine_diff_char_level(
            &line_diffs->diffs[i], lines_a, len_a, lines_b, len_b, options,
            &local_timeout
        );
        
        // Accumulate timeout status (VSCode: if (characterDiffs.hitTimeout) hitTimeout = true)
        if (local_timeout) {
            any_timeout = true;
        }
        
        if (char_mappings) {
            for (int j = 0; j < char_mappings->count; j++) {
                add_range_mapping(result, &char_mappings->mappings[j]);
            }
            free_range_mapping_array(char_mappings);
        }
    }
    
    // Propagate timeout status to caller
    if (out_hit_timeout) {
        *out_hit_timeout = any_timeout;
    }
    
    // Note: Whitespace-only change scanning happens in the main diff computer
    // (between line diffs), not here. This function only refines existing diffs.
    
    return result;
}

/**
 * Free RangeMappingArray
 */
void free_range_mapping_array(RangeMappingArray* arr) {
    if (!arr) return;
    if (arr->mappings) free(arr->mappings);
    free(arr);
}
