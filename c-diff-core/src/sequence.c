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
 */

#include "../include/sequence.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// ============================================================================
// Hash Function (FNV-1a)
// ============================================================================

/**
 * FNV-1a hash algorithm
 * Fast, good distribution, used by VSCode for string hashing
 * 
 * REUSED BY: LineSequence creation (hash trimmed lines)
 */
static uint32_t hash_string(const char* str) {
    uint32_t hash = 2166136261u;
    while (*str) {
        hash ^= (uint32_t)(unsigned char)(*str);
        hash *= 16777619u;
        str++;
    }
    return hash;
}

/**
 * Trim whitespace from both ends and hash the result
 * 
 * REUSED BY: LineSequence when ignore_whitespace is true
 */
static uint32_t hash_trimmed_string(const char* str) {
    if (!str) return 0;
    
    // Skip leading whitespace
    while (*str && isspace((unsigned char)*str)) {
        str++;
    }
    
    // Find end (non-whitespace)
    const char* end = str + strlen(str);
    while (end > str && isspace((unsigned char)*(end - 1))) {
        end--;
    }
    
    // Hash the trimmed portion
    uint32_t hash = 2166136261u;
    for (const char* p = str; p < end; p++) {
        hash ^= (uint32_t)(unsigned char)(*p);
        hash *= 16777619u;
    }
    return hash;
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
 * Boundary score for line sequences
 * 
 * Higher scores indicate better boundaries for diffs.
 * This guides the optimization to prefer natural breakpoints.
 * 
 * REUSED BY: Step 2 (shiftSequenceDiffs)
 */
static int line_seq_get_boundary_score(const ISequence* self, int length) {
    LineSequence* seq = (LineSequence*)self->data;
    
    if (length <= 0 || length > seq->length) {
        return 0;
    }
    
    // Check the line just before this boundary
    const char* line = seq->lines[length - 1];
    
    // Empty/whitespace-only lines are great boundaries
    bool is_blank = true;
    for (const char* p = line; *p; p++) {
        if (!isspace((unsigned char)*p)) {
            is_blank = false;
            break;
        }
    }
    if (is_blank) {
        return 50;  // High score for blank lines
    }
    
    // Skip leading whitespace to check structural characters
    while (*line && isspace((unsigned char)*line)) {
        line++;
    }
    
    // Structural characters (braces, brackets) are good boundaries
    if (*line == '{' || *line == '}' || 
        *line == '[' || *line == ']' ||
        *line == '(' || *line == ')') {
        
        // Check if rest is mostly whitespace
        const char* rest = line + 1;
        int non_ws = 0;
        while (*rest) {
            if (!isspace((unsigned char)*rest)) {
                non_ws++;
            }
            rest++;
        }
        
        if (non_ws <= 2) {
            return 30;  // Medium-high score for structural lines
        }
    }
    
    // Default: not a particularly good boundary
    return 5;
}

static void line_seq_destroy(ISequence* self) {
    LineSequence* seq = (LineSequence*)self->data;
    free(seq->trimmed_hash);
    free(seq);
    free(self);
}

/**
 * Create LineSequence wrapped in ISequence interface
 */
ISequence* line_sequence_create(const char** lines, int length, bool ignore_whitespace) {
    LineSequence* seq = (LineSequence*)malloc(sizeof(LineSequence));
    seq->lines = lines;  // Just reference, not owned
    seq->length = length;
    seq->ignore_whitespace = ignore_whitespace;
    
    // Pre-compute hashes for all lines
    seq->trimmed_hash = (uint32_t*)malloc(sizeof(uint32_t) * length);
    for (int i = 0; i < length; i++) {
        if (ignore_whitespace) {
            seq->trimmed_hash[i] = hash_trimmed_string(lines[i]);
        } else {
            seq->trimmed_hash[i] = hash_string(lines[i]);
        }
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
static int char_seq_get_boundary_score(const ISequence* self, int length) {
    CharSequence* seq = (CharSequence*)self->data;
    
    if (length <= 0 || length >= seq->length) {
        return 0;
    }
    
    uint32_t prev_char = length > 0 ? seq->elements[length - 1] : 0;
    uint32_t next_char = length < seq->length ? seq->elements[length] : 0;
    
    // Line breaks are highest priority boundaries
    if (prev_char == '\n') {
        return 150;
    }
    
    // Don't break between \r and \n
    if (prev_char == '\r' && next_char == '\n') {
        return 0;
    }
    
    int score = 0;
    
    // Check category transitions (letter->number, lower->upper, etc.)
    bool prev_is_word = (prev_char >= 'a' && prev_char <= 'z') ||
                        (prev_char >= 'A' && prev_char <= 'Z') ||
                        (prev_char >= '0' && prev_char <= '9');
    bool next_is_word = (next_char >= 'a' && next_char <= 'z') ||
                        (next_char >= 'A' && next_char <= 'Z') ||
                        (next_char >= '0' && next_char <= '9');
    
    // Transition between word and non-word
    if (prev_is_word != next_is_word) {
        score += 10;
    }
    
    // Whitespace boundaries
    if (prev_char == ' ' || prev_char == '\t') {
        score += 3;
    }
    if (next_char == ' ' || next_char == '\t') {
        score += 3;
    }
    
    // Punctuation/separator boundaries
    if (prev_char == ',' || prev_char == ';' || 
        prev_char == '.' || prev_char == ':') {
        score += 30;
    }
    
    return score;
}

static void char_seq_destroy(ISequence* self) {
    CharSequence* seq = (CharSequence*)self->data;
    free(seq->elements);
    free(seq->line_start_offsets);
    free(seq);
    free(self);
}

/**
 * Create CharSequence from line range
 * 
 * Concatenates lines with '\n' and tracks line boundaries
 * 
 * REUSED BY: Step 4 (refine.c) for each line-level diff
 */
ISequence* char_sequence_create(const char** lines, int start_line, int end_line, 
                                bool consider_whitespace) {
    if (start_line >= end_line) {
        // Empty sequence
        CharSequence* seq = (CharSequence*)malloc(sizeof(CharSequence));
        seq->elements = NULL;
        seq->length = 0;
        seq->line_start_offsets = NULL;
        seq->line_count = 0;
        seq->consider_whitespace = consider_whitespace;
        
        ISequence* iseq = (ISequence*)malloc(sizeof(ISequence));
        iseq->data = seq;
        iseq->getElement = char_seq_get_element;
        iseq->getLength = char_seq_get_length;
        iseq->isStronglyEqual = char_seq_is_strongly_equal;
        iseq->getBoundaryScore = char_seq_get_boundary_score;
        iseq->destroy = char_seq_destroy;
        return iseq;
    }
    
    CharSequence* seq = (CharSequence*)malloc(sizeof(CharSequence));
    seq->consider_whitespace = consider_whitespace;
    seq->line_count = end_line - start_line;
    seq->line_start_offsets = (int*)malloc(sizeof(int) * (seq->line_count + 1));
    
    // First pass: calculate total length
    int total_len = 0;
    for (int i = start_line; i < end_line; i++) {
        const char* line = lines[i];
        
        if (!consider_whitespace) {
            // Skip leading whitespace
            while (*line && isspace((unsigned char)*line)) {
                line++;
            }
            // Find end (trim trailing whitespace)
            const char* end = line + strlen(line);
            while (end > line && isspace((unsigned char)*(end - 1))) {
                end--;
            }
            total_len += (end - line);
        } else {
            total_len += strlen(line);
        }
        
        // Add newline except for last line
        if (i < end_line - 1) {
            total_len++;
        }
    }
    
    // Allocate elements array
    seq->elements = (uint32_t*)malloc(sizeof(uint32_t) * (total_len + 1));
    seq->length = total_len;
    
    // Second pass: fill elements and track line boundaries
    int offset = 0;
    for (int i = start_line; i < end_line; i++) {
        seq->line_start_offsets[i - start_line] = offset;
        
        const char* line = lines[i];
        const char* line_start = line;
        const char* line_end = line + strlen(line);
        
        if (!consider_whitespace) {
            // Trim whitespace
            while (*line_start && isspace((unsigned char)*line_start)) {
                line_start++;
            }
            while (line_end > line_start && isspace((unsigned char)*(line_end - 1))) {
                line_end--;
            }
        }
        
        // Copy characters
        for (const char* p = line_start; p < line_end; p++) {
            seq->elements[offset++] = (uint32_t)(unsigned char)*p;
        }
        
        // Add newline except for last line
        if (i < end_line - 1) {
            seq->elements[offset++] = '\n';
        }
    }
    
    // Store final offset (for bounds checking)
    seq->line_start_offsets[seq->line_count] = offset;
    
    // Create ISequence wrapper
    ISequence* iseq = (ISequence*)malloc(sizeof(ISequence));
    iseq->data = seq;
    iseq->getElement = char_seq_get_element;
    iseq->getLength = char_seq_get_length;
    iseq->isStronglyEqual = char_seq_is_strongly_equal;
    iseq->getBoundaryScore = char_seq_get_boundary_score;
    iseq->destroy = char_seq_destroy;
    
    return iseq;
}

/**
 * Translate character offset to (line, column) position
 * 
 * Binary search through line_start_offsets to find which line,
 * then calculate column within that line.
 * 
 * REUSED BY: Step 4 when converting character SequenceDiff to RangeMapping
 */
void char_sequence_translate_offset(const CharSequence* seq, int offset, 
                                    int* out_line, int* out_col) {
    if (!seq || offset < 0) {
        *out_line = 0;
        *out_col = 0;
        return;
    }
    
    // Binary search for line containing this offset
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
    *out_col = offset - seq->line_start_offsets[line_idx];
}

// =============================================================================
// CharSequence Extended Methods - VSCode LinesSliceCharSequence Parity
// =============================================================================

/**
 * Helper: Check if character is word character (alphanumeric)
 */
static bool is_word_char(uint32_t ch) {
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
 */
int char_sequence_count_lines_in(const CharSequence* seq, int start_offset, int end_offset) {
    if (!seq || start_offset < 0 || end_offset > seq->length || start_offset >= end_offset) {
        return 0;
    }
    
    int start_line, start_col, end_line, end_col;
    char_sequence_translate_offset(seq, start_offset, &start_line, &start_col);
    char_sequence_translate_offset(seq, end_offset, &end_line, &end_col);
    
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
 */
void char_sequence_extend_to_full_lines(const CharSequence* seq, 
                                       int start_offset, int end_offset,
                                       int* out_start, int* out_end) {
    if (!seq || start_offset < 0 || end_offset > seq->length) {
        *out_start = 0;
        *out_end = 0;
        return;
    }
    
    int start_line, start_col, end_line, end_col;
    char_sequence_translate_offset(seq, start_offset, &start_line, &start_col);
    char_sequence_translate_offset(seq, end_offset, &end_line, &end_col);
    
    // Extend to start of start_line
    int extended_start = seq->line_start_offsets[start_line];
    
    // Extend to start of next line after end_line (or end of sequence)
    int extended_end;
    if (end_line + 1 < seq->line_count) {
        extended_end = seq->line_start_offsets[end_line + 1];
    } else {
        extended_end = seq->length;
    }
    
    *out_start = extended_start;
    *out_end = extended_end;
}

