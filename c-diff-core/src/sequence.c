/**
 * Sequence Abstraction Implementation
 * 
 * Implements ISequence interface for both LineSequence and CharSequence.
 * This infrastructure is reused throughout the diff pipeline.
 * 
 * VSCode References:
 * - lineSequence.ts
 * - linesSliceCharSequence.ts
 * - diffAlgorithm.ts (ISequence interface)
 * 
 * VSCode Parity: 100% for perfect hash and boundary scoring
 */

#include "../include/sequence.h"
#include "../include/string_hash_map.h"
#include "../include/platform.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <limits.h>
#include <stdint.h>

// ============================================================================
// UTF-8 Character Counting
// ============================================================================

/**
 * Count UTF-8 characters in a string (NOT bytes)
 * JavaScript counts Unicode characters, not bytes.
 * This matches JavaScript's string.length behavior.
 */
static int utf8_strlen(const char* str) {
    if (!str) return 0;
    
    int char_count = 0;
    const unsigned char* p = (const unsigned char*)str;
    
    while (*p) {
        if (*p < 0x80) {
            // ASCII (1 byte)
            p++;
        } else if ((*p & 0xE0) == 0xC0) {
            // 2-byte sequence
            p += 2;
        } else if ((*p & 0xF0) == 0xE0) {
            // 3-byte sequence
            p += 3;
        } else if ((*p & 0xF8) == 0xF0) {
            // 4-byte sequence
            p += 4;
        } else {
            // Invalid UTF-8, skip byte
            p++;
        }
        char_count++;
    }
    
    return char_count;
}

/**
 * Convert character position to byte offset in UTF-8 string
 * @param str The UTF-8 string
 * @param char_pos Character position (0-based)
 * @return Byte offset (0-based)
 */
static int utf8_char_to_byte_offset(const char* str, int char_pos) {
    if (!str || char_pos <= 0) return 0;
    
    int char_count = 0;
    const unsigned char* p = (const unsigned char*)str;
    const unsigned char* start = p;
    
    while (*p && char_count < char_pos) {
        if (*p < 0x80) {
            p++;
        } else if ((*p & 0xE0) == 0xC0) {
            if (p[1]) p += 2; else p++;
        } else if ((*p & 0xF0) == 0xE0) {
            if (p[1] && p[2]) p += 3; else p++;
        } else if ((*p & 0xF8) == 0xF0) {
            if (p[1] && p[2] && p[3]) p += 4; else p++;
        } else {
            p++;
        }
        char_count++;
    }
    
    return (int)(p - start);
}

/**
 * Convert byte offset to character position in UTF-8 string
 * @param str The UTF-8 string
 * @param byte_offset Byte offset (0-based)
 * @return Character position (0-based)
 */
static int utf8_byte_to_char_offset(const char* str, int byte_offset) {
    if (!str || byte_offset <= 0) return 0;
    
    int char_count = 0;
    const unsigned char* p = (const unsigned char*)str;
    const unsigned char* end = p + byte_offset;
    
    while (*p && p < end) {
        if (*p < 0x80) {
            p++;
        } else if ((*p & 0xE0) == 0xC0) {
            p += 2;
        } else if ((*p & 0xF0) == 0xE0) {
            p += 3;
        } else if ((*p & 0xF8) == 0xF0) {
            p += 4;
        } else {
            p++;
        }
        char_count++;
    }
    
    return char_count;
}

// ============================================================================
// String Trimming Utilities
// ============================================================================

/**
 * Create a trimmed copy of string (caller must free)
 */
static char* trim_string(const char* str) {
    if (!str) return diff_strdup("");
    
    // Skip leading whitespace
    while (*str && isspace((unsigned char)*str)) {
        str++;
    }
    
    // Find end (non-whitespace)
    const char* end = str + strlen(str);
    while (end > str && isspace((unsigned char)*(end - 1))) {
        end--;
    }
    
    // Copy trimmed portion
    int len = end - str;
    char* result = (char*)malloc(len + 1);
    memcpy(result, str, len);
    result[len] = '\0';
    return result;
}

// ============================================================================
// LineSequence Implementation
// ============================================================================

/**
 * LineSequence vtable functions
 */
static uint32_t line_seq_get_element(const ISequence* self, int offset) {
    LineSequence* seq = (LineSequence*)self->data;
    if (offset < 0 || offset >= seq->length) {
        return 0;
    }
    return seq->trimmed_hash[offset];
}

static int line_seq_get_length(const ISequence* self) {
    LineSequence* seq = (LineSequence*)self->data;
    return seq->length;
}

static bool line_seq_is_strongly_equal(const ISequence* self, int offset1, int offset2) {
    LineSequence* seq = (LineSequence*)self->data;
    if (offset1 < 0 || offset1 >= seq->length || 
        offset2 < 0 || offset2 >= seq->length) {
        return false;
    }
    // Strong equality checks original lines (including whitespace)
    return strcmp(seq->lines[offset1], seq->lines[offset2]) == 0;
}

/**
 * Get indentation count for a line
 * 
 * Counts leading spaces and tabs, matching VSCode's getIndentation().
 * 
 * VSCode Reference: lineSequence.ts getIndentation()
 * VSCode Parity: 100%
 */
static int get_indentation(const char* line) {
    int count = 0;
    while (*line && (*line == ' ' || *line == '\t')) {
        count++;
        line++;
    }
    return count;
}

/**
 * Boundary score for line sequences - VSCode Parity
 * 
 * Higher scores indicate better boundaries for diffs.
 * Uses indentation-based scoring matching VSCode exactly:
 * score = 1000 - (indentationBefore + indentationAfter)
 * 
 * Lines with less indentation are better boundaries.
 * 
 * VSCode Reference: lineSequence.ts getBoundaryScore()
 * VSCode Parity: 100%
 * 
 * REUSED BY: Step 2 (shiftSequenceDiffs)
 */
static int line_seq_get_boundary_score(const ISequence* self, int length) {
    LineSequence* seq = (LineSequence*)self->data;
    
    if (length < 0 || length > seq->length) {
        return 0;
    }
    
    // Indentation before boundary (line at length-1)
    int indent_before = 0;
    if (length > 0) {
        indent_before = get_indentation(seq->lines[length - 1]);
    }
    
    // Indentation after boundary (line at length)
    int indent_after = 0;
    if (length < seq->length) {
        indent_after = get_indentation(seq->lines[length]);
    }
    
    // VSCode formula: 1000 - (indentBefore + indentAfter)
    // Lower indentation = higher score = better boundary
    return 1000 - (indent_before + indent_after);
}

static void line_seq_destroy(ISequence* self) {
    LineSequence* seq = (LineSequence*)self->data;
    free(seq->trimmed_hash);
    free(seq);
    free(self);
}

/**
 * Create LineSequence wrapped in ISequence interface with perfect hash
 * 
 * VSCode Parity: 100%
 * - Uses perfect hash (collision-free) like Map<string, number>
 * - Boundary scoring uses indentation matching VSCode exactly
 */
ISequence* line_sequence_create(const char** lines, int length, bool ignore_whitespace,
                               StringHashMap* hash_map) {
    LineSequence* seq = (LineSequence*)malloc(sizeof(LineSequence));
    seq->lines = lines;  // Just reference, not owned
    seq->length = length;
    seq->ignore_whitespace = ignore_whitespace;
    
    // Create internal hash map if not provided
    bool owns_hash_map = false;
    if (!hash_map) {
        hash_map = string_hash_map_create();
        owns_hash_map = true;
    }
    
    // Pre-compute perfect hashes for all lines
    seq->trimmed_hash = (uint32_t*)malloc(sizeof(uint32_t) * length);
    for (int i = 0; i < length; i++) {
        if (ignore_whitespace) {
            char* trimmed = trim_string(lines[i]);
            seq->trimmed_hash[i] = string_hash_map_get_or_create(hash_map, trimmed);
            free(trimmed);
        } else {
            seq->trimmed_hash[i] = string_hash_map_get_or_create(hash_map, lines[i]);
        }
    }
    
    // Destroy internal hash map if we created it
    if (owns_hash_map) {
        string_hash_map_destroy(hash_map);
    }
    
    // Create ISequence wrapper
    ISequence* iseq = (ISequence*)malloc(sizeof(ISequence));
    iseq->data = seq;
    iseq->getElement = line_seq_get_element;
    iseq->getLength = line_seq_get_length;
    iseq->isStronglyEqual = line_seq_is_strongly_equal;
    iseq->getBoundaryScore = line_seq_get_boundary_score;
    iseq->destroy = line_seq_destroy;
    
    return iseq;
}

// ============================================================================
// CharSequence Implementation
// ============================================================================

/**
 * CharSequence vtable functions
 */
static uint32_t char_seq_get_element(const ISequence* self, int offset) {
    CharSequence* seq = (CharSequence*)self->data;
    if (offset < 0 || offset >= seq->length) {
        return 0;
    }
    return seq->elements[offset];
}

static int char_seq_get_length(const ISequence* self) {
    CharSequence* seq = (CharSequence*)self->data;
    return seq->length;
}

static bool char_seq_is_strongly_equal(const ISequence* self, int offset1, int offset2) {
    CharSequence* seq = (CharSequence*)self->data;
    if (offset1 < 0 || offset1 >= seq->length || 
        offset2 < 0 || offset2 >= seq->length) {
        return false;
    }
    // For characters, element equality is strong equality
    return seq->elements[offset1] == seq->elements[offset2];
}

/**
 * Boundary score for character sequences
 * 
 * Helps character-level diffs align to word boundaries, whitespace, etc.
 * 
 * REUSED BY: Step 4 (character optimization)
 * 
 * VSCode Reference: linesSliceCharSequence.ts getBoundaryScore()
 */
typedef enum {
    CHAR_BOUNDARY_WORD_LOWER,
    CHAR_BOUNDARY_WORD_UPPER,
    CHAR_BOUNDARY_WORD_NUMBER,
    CHAR_BOUNDARY_END,
    CHAR_BOUNDARY_OTHER,
    CHAR_BOUNDARY_SEPARATOR,
    CHAR_BOUNDARY_SPACE,
    CHAR_BOUNDARY_LINE_BREAK_CR,
    CHAR_BOUNDARY_LINE_BREAK_LF
} CharBoundaryCategory;

static CharBoundaryCategory get_char_category(int char_code) {
    if (char_code == '\n') {
        return CHAR_BOUNDARY_LINE_BREAK_LF;
    } else if (char_code == '\r') {
        return CHAR_BOUNDARY_LINE_BREAK_CR;
    } else if (char_code == ' ' || char_code == '\t') {
        return CHAR_BOUNDARY_SPACE;
    } else if (char_code >= 'a' && char_code <= 'z') {
        return CHAR_BOUNDARY_WORD_LOWER;
    } else if (char_code >= 'A' && char_code <= 'Z') {
        return CHAR_BOUNDARY_WORD_UPPER;
    } else if (char_code >= '0' && char_code <= '9') {
        return CHAR_BOUNDARY_WORD_NUMBER;
    } else if (char_code == -1) {
        return CHAR_BOUNDARY_END;
    } else if (char_code == ',' || char_code == ';') {
        return CHAR_BOUNDARY_SEPARATOR;
    } else {
        return CHAR_BOUNDARY_OTHER;
    }
}

static int get_category_boundary_score(CharBoundaryCategory category) {
    static const int scores[] = {
        [CHAR_BOUNDARY_WORD_LOWER] = 0,
        [CHAR_BOUNDARY_WORD_UPPER] = 0,
        [CHAR_BOUNDARY_WORD_NUMBER] = 0,
        [CHAR_BOUNDARY_END] = 10,
        [CHAR_BOUNDARY_OTHER] = 2,
        [CHAR_BOUNDARY_SEPARATOR] = 30,
        [CHAR_BOUNDARY_SPACE] = 3,
        [CHAR_BOUNDARY_LINE_BREAK_CR] = 10,
        [CHAR_BOUNDARY_LINE_BREAK_LF] = 10
    };
    return scores[category];
}

static int char_seq_get_boundary_score(const ISequence* self, int length) {
    CharSequence* seq = (CharSequence*)self->data;
    
    int prev_char = (length > 0) ? (int)seq->elements[length - 1] : -1;
    int next_char = (length < seq->length) ? (int)seq->elements[length] : -1;
    
    CharBoundaryCategory prev_category = get_char_category(prev_char);
    CharBoundaryCategory next_category = get_char_category(next_char);
    
    // Don't break between \r and \n
    if (prev_category == CHAR_BOUNDARY_LINE_BREAK_CR && 
        next_category == CHAR_BOUNDARY_LINE_BREAK_LF) {
        return 0;
    }
    
    // Prefer the linebreak before the change
    if (prev_category == CHAR_BOUNDARY_LINE_BREAK_LF) {
        return 150;
    }
    
    int score = 0;
    
    // Category transition bonus
    if (prev_category != next_category) {
        score += 10;
        
        // CamelCase bonus: lower -> upper
        if (prev_category == CHAR_BOUNDARY_WORD_LOWER && 
            next_category == CHAR_BOUNDARY_WORD_UPPER) {
            score += 1;
        }
    }
    
    // Add boundary scores from both categories
    score += get_category_boundary_score(prev_category);
    score += get_category_boundary_score(next_category);
    
    return score;
}

static void char_seq_destroy(ISequence* self) {
    CharSequence* seq = (CharSequence*)self->data;
    free(seq->elements);
    free(seq->line_start_offsets);
    free(seq->trimmed_ws_lengths);
    free(seq->original_line_start_cols);
    free(seq);
    free(self);
}

/**
 * Create CharSequence from line range
 * 
 * Concatenates lines with '\n' and tracks line boundaries
 * 
 * REUSED BY: Step 4 (char_level.c) for each line-level diff
 */
static ISequence* char_sequence_create_empty(bool consider_whitespace) {
    CharSequence* seq = (CharSequence*)malloc(sizeof(CharSequence));
    if (!seq) {
        return NULL;
    }
    seq->elements = NULL;
    seq->length = 0;
    seq->line_start_offsets = NULL;
    seq->trimmed_ws_lengths = NULL;
    seq->original_line_start_cols = NULL;
    seq->line_count = 0;
    seq->consider_whitespace = consider_whitespace;

    ISequence* iseq = (ISequence*)malloc(sizeof(ISequence));
    if (!iseq) {
        free(seq);
        return NULL;
    }
    iseq->data = seq;
    iseq->getElement = char_seq_get_element;
    iseq->getLength = char_seq_get_length;
    iseq->isStronglyEqual = char_seq_is_strongly_equal;
    iseq->getBoundaryScore = char_seq_get_boundary_score;
    iseq->destroy = char_seq_destroy;
    return iseq;
}

ISequence* char_sequence_create(const char** lines, int start_line, int end_line,
                                bool consider_whitespace) {
    if (start_line >= end_line) {
        return char_sequence_create_empty(consider_whitespace);
    }

    CharRange range;
    range.start_line = start_line + 1;
    range.start_col = 1;

    int last_line_index = end_line - 1;
    if (last_line_index < start_line) {
        range.end_line = range.start_line;
        range.end_col = range.start_col;
    } else {
        range.end_line = last_line_index + 1;
        const char* last_line = lines[last_line_index];
        int last_length = last_line ? (int)strlen(last_line) : 0;
        range.end_col = last_length + 1;
    }

    return char_sequence_create_from_range(lines, end_line, &range, consider_whitespace);
}

ISequence* char_sequence_create_from_range(const char** lines,
                                           int line_count,
                                           const CharRange* range,
                                           bool consider_whitespace) {
    if (!range || !lines) {
        return char_sequence_create_empty(consider_whitespace);
    }

    if (range->start_line > range->end_line) {
        return char_sequence_create_empty(consider_whitespace);
    }

    if (line_count <= 0) {
        return char_sequence_create_empty(consider_whitespace);
    }

    int start_line_num = range->start_line;
    int end_line_num = range->end_line;

    if (start_line_num < 1) {
        start_line_num = 1;
    }
    if (start_line_num > line_count) {
        start_line_num = line_count;
    }

    if (end_line_num < start_line_num) {
        end_line_num = start_line_num;
    }
    if (end_line_num > line_count) {
        end_line_num = line_count;
    }

    int line_span = end_line_num - start_line_num + 1;
    if (line_span <= 0) {
        return char_sequence_create_empty(consider_whitespace);
    }

    CharSequence* seq = (CharSequence*)malloc(sizeof(CharSequence));
    if (!seq) {
        return NULL;
    }
    seq->consider_whitespace = consider_whitespace;
    seq->line_count = line_span;
    seq->elements = NULL;
    seq->line_start_offsets = (int*)malloc(sizeof(int) * (line_span + 1));
    seq->trimmed_ws_lengths = (int*)malloc(sizeof(int) * line_span);
    seq->original_line_start_cols = (int*)malloc(sizeof(int) * line_span);
    if (!seq->line_start_offsets || !seq->trimmed_ws_lengths || !seq->original_line_start_cols) {
        free(seq->line_start_offsets);
        free(seq->trimmed_ws_lengths);
        free(seq->original_line_start_cols);
        free(seq);
        return NULL;
    }

    int* effective_lengths = (int*)malloc(sizeof(int) * line_span);
    if (!effective_lengths) {
        free(seq->line_start_offsets);
        free(seq->trimmed_ws_lengths);
        free(seq->original_line_start_cols);
        free(seq);
        return NULL;
    }

    int total_len = 0;
    for (int idx = 0; idx < line_span; idx++) {
        int line_number = start_line_num + idx;
        const char* line = (line_number >= 1 && line_number <= line_count)
                               ? lines[line_number - 1]
                               : "";
        if (!line) {
            line = "";
        }
        int line_len_bytes = (int)strlen(line);
        int line_len_chars = utf8_strlen(line);

        // range->start_col is a CHARACTER position, convert to byte offset
        int line_start_char_offset = 0;
        int line_start_byte_offset = 0;
        if (line_number == range->start_line && range->start_col > 1) {
            line_start_char_offset = range->start_col - 1;
            if (line_start_char_offset > line_len_chars) {
                line_start_char_offset = line_len_chars;
            }
            line_start_byte_offset = utf8_char_to_byte_offset(line, line_start_char_offset);
        }
        seq->original_line_start_cols[idx] = line_start_char_offset;

        const char* substring_start = line + line_start_byte_offset;
        int substring_len = line_len_bytes - line_start_byte_offset;
        if (substring_len < 0) {
            substring_len = 0;
        }

        int trimmed_ws_length_chars = 0;
        const char* trimmed_start = substring_start;
        const char* trimmed_end = substring_start + substring_len;

        if (!consider_whitespace) {
            const char* ws_start = trimmed_start;
            while (trimmed_start < trimmed_end && isspace((unsigned char)*trimmed_start)) {
                trimmed_start++;
            }
            // Count characters, not bytes, in the trimmed whitespace
            trimmed_ws_length_chars = utf8_byte_to_char_offset(ws_start, (int)(trimmed_start - ws_start));
            
            while (trimmed_end > trimmed_start && isspace((unsigned char)*(trimmed_end - 1))) {
                trimmed_end--;
            }
        }

        int trimmed_len_bytes = (int)(trimmed_end - trimmed_start);
        if (trimmed_len_bytes < 0) {
            trimmed_len_bytes = 0;
        }
        int trimmed_len_chars = utf8_byte_to_char_offset(trimmed_start, trimmed_len_bytes);

        // line_length is in CHARACTERS for column calculation
        int line_length_chars = trimmed_len_chars;
        int line_length_bytes = trimmed_len_bytes;
        
        if (line_number == end_line_num) {
            long long end_column_exclusive = (long long)range->end_col - 1;
            long long available_chars = end_column_exclusive - line_start_char_offset - trimmed_ws_length_chars;
            if (available_chars < 0) {
                line_length_chars = 0;
                line_length_bytes = 0;
            } else if (available_chars < line_length_chars) {
                line_length_chars = (int)available_chars;
                // Convert character length to byte length
                line_length_bytes = utf8_char_to_byte_offset(trimmed_start, line_length_chars);
            }
        }

        if (line_length_chars < 0) {
            line_length_chars = 0;
            line_length_bytes = 0;
        }
        if (line_length_chars > trimmed_len_chars) {
            line_length_chars = trimmed_len_chars;
            line_length_bytes = trimmed_len_bytes;
        }

        seq->trimmed_ws_lengths[idx] = trimmed_ws_length_chars;
        effective_lengths[idx] = line_length_bytes;  // Store BYTES for elements array

        total_len += line_length_bytes;  // Count BYTES for elements array
        if (line_number < end_line_num) {
            total_len += 1;  // For '\n'
        }
    }

    seq->elements = (uint32_t*)malloc(sizeof(uint32_t) * (total_len + 1));
    if (!seq->elements) {
        free(effective_lengths);
        free(seq->line_start_offsets);
        free(seq->trimmed_ws_lengths);
        free(seq->original_line_start_cols);
        free(seq);
        return NULL;
    }
    seq->length = total_len;

    int offset = 0;
    for (int idx = 0; idx < line_span; idx++) {
        int line_number = start_line_num + idx;
        seq->line_start_offsets[idx] = offset;

        const char* line = (line_number >= 1 && line_number <= line_count)
                               ? lines[line_number - 1]
                               : "";
        if (!line) {
            line = "";
        }
        int line_len_chars = utf8_strlen(line);

        int start_col_chars = seq->original_line_start_cols[idx];
        if (!consider_whitespace) {
            start_col_chars += seq->trimmed_ws_lengths[idx];
        }
        if (start_col_chars > line_len_chars) {
            start_col_chars = line_len_chars;
        }

        int len_bytes = effective_lengths[idx];  // This is already in bytes
        if (len_bytes < 0) {
            len_bytes = 0;
        }

        // Convert character position to byte offset for actual string access
        int start_col_bytes = utf8_char_to_byte_offset(line, start_col_chars);

        const char* src = line + start_col_bytes;
        for (int j = 0; j < len_bytes; j++) {
            seq->elements[offset++] = (uint32_t)(unsigned char)src[j];
        }

        if (line_number < end_line_num) {
            seq->elements[offset++] = '\n';
        }
    }
    seq->line_start_offsets[line_span] = offset;

    free(effective_lengths);

    ISequence* iseq = (ISequence*)malloc(sizeof(ISequence));
    if (!iseq) {
        free(seq->elements);
        free(seq->line_start_offsets);
        free(seq->trimmed_ws_lengths);
        free(seq->original_line_start_cols);
        free(seq);
        return NULL;
    }
    iseq->data = seq;
    iseq->getElement = char_seq_get_element;
    iseq->getLength = char_seq_get_length;
    iseq->isStronglyEqual = char_seq_is_strongly_equal;
    iseq->getBoundaryScore = char_seq_get_boundary_score;
    iseq->destroy = char_seq_destroy;

    return iseq;
}

/**
 * Translate character offset to (line, column) position - VSCode Parity
 * 
 * Binary search through line_start_offsets to find which line,
 * then calculate column within that line, accounting for trimmed whitespace.
 * 
 * VSCode: LinesSliceCharSequence.translateOffset()
 * Key logic: ((lineOffset === 0 && preference === 'left') ? 0 : this.trimmedWsLengthsByLineIdx[i])
 * 
 * REUSED BY: Step 4 when converting character SequenceDiff to RangeMapping
 */
void char_sequence_translate_offset(const CharSequence* seq, int offset,
                                    OffsetPreference preference,
                                    int* out_line, int* out_col) {
    if (!seq || offset < 0 || seq->line_count == 0 || !seq->line_start_offsets) {
        *out_line = 0;
        *out_col = 0;
        return;
    }
    
    // Binary search for line containing this offset
    // VSCode: findLastIdxMonotonous(this.firstElementOffsetByLineIdx, (value) => value <= offset)
    int left = 0;
    int right = seq->line_count;
    
    while (left < right) {
        int mid = (left + right) / 2;
        if (seq->line_start_offsets[mid] <= offset) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    
    int line_idx = left - 1;
    if (line_idx < 0) line_idx = 0;
    if (line_idx >= seq->line_count) line_idx = seq->line_count - 1;
    
    *out_line = line_idx;
    
    // Calculate column offset within the line
    // VSCode: const lineOffset = offset - this.firstElementOffsetByLineIdx[i];
    int line_offset = offset - seq->line_start_offsets[line_idx];
    
    // VSCode: 1 + this.lineStartOffsets[i] + lineOffset + 
    //         ((lineOffset === 0 && preference === 'left') ? 0 : this.trimmedWsLengthsByLineIdx[i])
    // Note: VSCode returns 1-based, we return 0-based, so we omit the "+ 1"
    int trimmed_ws = seq->trimmed_ws_lengths ? seq->trimmed_ws_lengths[line_idx] : 0;
    int original_line_start = seq->original_line_start_cols ? seq->original_line_start_cols[line_idx] : 0;
    
    // Key parity fix: only add trimmed whitespace if NOT (at line start AND left preference)
    int add_trimmed_ws = (line_offset == 0 && preference == OFFSET_PREFERENCE_LEFT) ? 0 : trimmed_ws;
    
    *out_col = original_line_start + line_offset + add_trimmed_ws;
}

/**
 * Translate character offset range to position range - VSCode Parity
 * 
 * VSCode: LinesSliceCharSequence.translateRange()
 * Logic:
 *   const pos1 = this.translateOffset(range.start, 'right');
 *   const pos2 = this.translateOffset(range.endExclusive, 'left');
 *   if (pos2.isBefore(pos1)) return Range.fromPositions(pos2, pos2);
 *   return Range.fromPositions(pos1, pos2);
 * 
 * REUSED BY: Step 4 (char_level.c) when converting SequenceDiff to RangeMapping
 */
void char_sequence_translate_range(const CharSequence* seq,
                                   int start_offset, int end_offset,
                                   int* out_start_line, int* out_start_col,
                                   int* out_end_line, int* out_end_col) {
    // VSCode: const pos1 = this.translateOffset(range.start, 'right');
    char_sequence_translate_offset(seq, start_offset, OFFSET_PREFERENCE_RIGHT,
                                   out_start_line, out_start_col);
    
    // VSCode: const pos2 = this.translateOffset(range.endExclusive, 'left');
    char_sequence_translate_offset(seq, end_offset, OFFSET_PREFERENCE_LEFT,
                                   out_end_line, out_end_col);
    
    // VSCode: if (pos2.isBefore(pos1)) return Range.fromPositions(pos2, pos2);
    // Check if end position is before start position
    if (*out_end_line < *out_start_line ||
        (*out_end_line == *out_start_line && *out_end_col < *out_start_col)) {
        // Collapse to end position
        *out_start_line = *out_end_line;
        *out_start_col = *out_end_col;
    }
}

// =============================================================================
// CharSequence Extended Methods - VSCode LinesSliceCharSequence Parity
// =============================================================================

/**
 * Helper: Check if character is word character (alphanumeric + underscore)
 */
static bool is_word_char(uint32_t ch) {
    // VSCode's isWordChar: only alphanumeric (a-z, A-Z, 0-9)
    // Does NOT include underscore!
    return (ch >= 'a' && ch <= 'z') ||
           (ch >= 'A' && ch <= 'Z') ||
           (ch >= '0' && ch <= '9');
}

/**
 * Helper: Check if character is uppercase
 */
static bool is_upper_case(uint32_t ch) {
    return (ch >= 'A' && ch <= 'Z');
}

/**
 * Find word containing offset - VSCode Parity
 */
bool char_sequence_find_word_containing(const CharSequence* seq, int offset,
                                       int* out_start, int* out_end) {
    if (!seq || offset < 0 || offset >= seq->length) {
        return false;
    }
    
    if (!is_word_char(seq->elements[offset])) {
        return false;
    }
    
    // Find start of word
    int start = offset;
    while (start > 0 && is_word_char(seq->elements[start - 1])) {
        start--;
    }
    
    // Find end of word
    int end = offset;
    while (end < seq->length && is_word_char(seq->elements[end])) {
        end++;
    }
    
    *out_start = start;
    *out_end = end;
    return true;
}

/**
 * Find subword containing offset - VSCode Parity
 * 
 * For CamelCase: "fooBar" has subwords "foo" and "Bar"
 */
bool char_sequence_find_subword_containing(const CharSequence* seq, int offset,
                                          int* out_start, int* out_end) {
    if (!seq || offset < 0 || offset >= seq->length) {
        return false;
    }
    
    if (!is_word_char(seq->elements[offset])) {
        return false;
    }
    
    // Find start of subword (stop at uppercase boundary)
    int start = offset;
    while (start > 0 && is_word_char(seq->elements[start - 1]) && 
           !is_upper_case(seq->elements[start])) {
        start--;
    }
    
    // Find end of subword (stop at uppercase boundary)
    int end = offset;
    while (end < seq->length && is_word_char(seq->elements[end]) && 
           !is_upper_case(seq->elements[end])) {
        end++;
    }
    
    *out_start = start;
    *out_end = end;
    return true;
}

/**
 * Count lines in character range - VSCode Parity
 * 
 * VSCode: LinesSliceCharSequence.countLinesIn()
 * Logic: this.translateOffset(range.endExclusive).lineNumber - this.translateOffset(range.start).lineNumber
 * Note: VSCode uses default preference ('right') for both positions
 */
int char_sequence_count_lines_in(const CharSequence* seq, int start_offset, int end_offset) {
    if (!seq || start_offset < 0 || end_offset > seq->length || start_offset >= end_offset) {
        return 0;
    }
    
    int start_line, start_col, end_line, end_col;
    // VSCode: uses default 'right' preference for both
    char_sequence_translate_offset(seq, start_offset, OFFSET_PREFERENCE_RIGHT, &start_line, &start_col);
    char_sequence_translate_offset(seq, end_offset, OFFSET_PREFERENCE_RIGHT, &end_line, &end_col);
    
    return end_line - start_line;
}

/**
 * Get text for range - VSCode Parity
 */
char* char_sequence_get_text(const CharSequence* seq, int start_offset, int end_offset) {
    if (!seq || start_offset < 0 || end_offset > seq->length || start_offset > end_offset) {
        return NULL;
    }
    
    int len = end_offset - start_offset;
    char* result = (char*)malloc(len + 1);
    if (!result) return NULL;
    
    for (int i = 0; i < len; i++) {
        result[i] = (char)seq->elements[start_offset + i];
    }
    result[len] = '\0';
    
    return result;
}

/**
 * Extend range to full lines - VSCode Parity
 * 
 * VSCode: LinesSliceCharSequence.extendToFullLines()
 * Logic:
 *   const start = findLastMonotonous(this.firstElementOffsetByLineIdx, x => x <= range.start) ?? 0;
 *   const end = findFirstMonotonous(this.firstElementOffsetByLineIdx, x => range.endExclusive <= x) ?? this.elements.length;
 * 
 * Note: VSCode does NOT use translateOffset! It directly searches line_start_offsets array.
 */
void char_sequence_extend_to_full_lines(const CharSequence* seq, 
                                       int start_offset, int end_offset,
                                       int* out_start, int* out_end) {
    if (!seq || start_offset < 0 || end_offset > seq->length) {
        *out_start = 0;
        *out_end = 0;
        return;
    }
    
    // VSCode: findLastMonotonous(firstElementOffsetByLineIdx, x => x <= range.start) ?? 0
    // Find the last line start offset that is <= start_offset
    int extended_start = 0;
    for (int i = seq->line_count - 1; i >= 0; i--) {
        if (seq->line_start_offsets[i] <= start_offset) {
            extended_start = seq->line_start_offsets[i];
            break;
        }
    }
    
    // VSCode: findFirstMonotonous(firstElementOffsetByLineIdx, x => range.endExclusive <= x) ?? elements.length
    // Find the first line start offset that is >= end_offset (or use seq->length)
    int extended_end = seq->length;
    for (int i = 0; i < seq->line_count; i++) {
        if (end_offset <= seq->line_start_offsets[i]) {
            extended_end = seq->line_start_offsets[i];
            break;
        }
    }
    
    *out_start = extended_start;
    *out_end = extended_end;
}
