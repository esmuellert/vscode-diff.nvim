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
ISequence* char_sequence_create(const char** lines, int start_line, int end_line, 
                                bool consider_whitespace) {
    if (start_line >= end_line) {
        // Empty sequence
        CharSequence* seq = (CharSequence*)malloc(sizeof(CharSequence));
        seq->elements = NULL;
        seq->length = 0;
        seq->line_start_offsets = NULL;
        seq->trimmed_ws_lengths = NULL;
        seq->original_line_start_cols = NULL;
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
    seq->trimmed_ws_lengths = (int*)malloc(sizeof(int) * seq->line_count);
    seq->original_line_start_cols = (int*)malloc(sizeof(int) * seq->line_count);
    
    // First pass: calculate total length and track trim info
    int total_len = 0;
    for (int i = start_line; i < end_line; i++) {
        const char* line = lines[i];
        const char* line_start = line;
        int trimmed_leading = 0;
        
        if (!consider_whitespace) {
            // Count and skip leading whitespace
            while (*line_start && isspace((unsigned char)*line_start)) {
                line_start++;
                trimmed_leading++;
            }
            // Find end (trim trailing whitespace)
            const char* line_end = line_start + strlen(line_start);
            while (line_end > line_start && isspace((unsigned char)*(line_end - 1))) {
                line_end--;
            }
            total_len += (line_end - line_start);
        } else {
            total_len += strlen(line);
        }
        
        // Store trim info (VSCode: trimmedWsLengthsByLineIdx and lineStartOffsets)
        seq->trimmed_ws_lengths[i - start_line] = trimmed_leading;
        seq->original_line_start_cols[i - start_line] = 0; // Will be set if needed for range support
        
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
    if (!seq || offset < 0) {
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

