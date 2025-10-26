#ifndef SEQUENCE_H
#define SEQUENCE_H

#include <stdint.h>
#include <stdbool.h>

/**
 * Generic Sequence Interface
 * 
 * Maps to VSCode's ISequence interface.
 * This abstraction allows the Myers algorithm and optimization functions
 * to work on any sequence type (lines, characters, etc.) without modification.
 * 
 * REUSED BY:
 * - Step 1 (myers.c): Myers algorithm operates on ISequence
 * - Step 2-3 (optimize.c): Optimization functions use getBoundaryScore()
 * - Step 4 (char_level.c): Character sequences implement this interface
 * 
 * VSCode Reference: src/vs/editor/common/diff/defaultLinesDiffComputer/algorithms/diffAlgorithm.ts
 */
typedef struct ISequence ISequence;

struct ISequence {
    // Opaque data pointer - actual sequence implementation
    void* data;
    
    // Function pointers (vtable pattern)
    
    /**
     * Get element at offset (typically returns hash/code for fast comparison)
     * 
     * For LineSequence: Returns hash of trimmed line
     * For CharSequence: Returns character code
     * 
     * REUSED BY: Step 1 (Myers), Step 2-3 (optimize), Step 4 (char_level)
     */
    uint32_t (*getElement)(const ISequence* self, int offset);
    
    /**
     * Get length of sequence
     * 
     * REUSED BY: Step 1 (Myers), Step 2-3 (optimize), Step 4 (char_level)
     */
    int (*getLength)(const ISequence* self);
    
    /**
     * Check if two elements are strongly equal (exact comparison)
     * 
     * For LineSequence: Compares original lines including whitespace
     * For CharSequence: Compares character codes exactly
     * 
     * This is used when getElement() returns hashes - we need to verify
     * that hash collision didn't occur.
     * 
     * REUSED BY: Step 2 (joinSequenceDiffsByShifting)
     */
    bool (*isStronglyEqual)(const ISequence* self, int offset1, int offset2);
    
    /**
     * Get boundary score at position (higher = better boundary)
     * 
     * Used by optimization to shift diffs to natural boundaries like:
     * - Blank lines (score: high)
     * - Structural characters: {, }, [, ] (score: medium)
     * - Whitespace (score: low)
     * - Line breaks (score: very high)
     * 
     * REUSED BY: Step 2 (shiftSequenceDiffs), Step 4 (character optimization)
     * 
     * Optional: Can be NULL if sequence doesn't support boundary scoring
     */
    int (*getBoundaryScore)(const ISequence* self, int length);
    
    /**
     * Cleanup function - called when sequence is destroyed
     */
    void (*destroy)(ISequence* self);
};

/**
 * LineSequence - Sequence of lines with hash-based comparison
 * 
 * Implements ISequence for line-level diffing.
 * Uses perfect hash (collision-free) of trimmed lines for comparison,
 * matching VSCode's Map<string, number> approach exactly.
 * 
 * REUSED BY: Step 1 (Myers on lines), Step 2-3 (line optimization)
 * 
 * VSCode Reference: src/vs/editor/common/diff/defaultLinesDiffComputer/lineSequence.ts
 * VSCode Parity: 100% - Perfect hash guarantees no collisions
 */
typedef struct {
    const char** lines;      // Original lines (NOT owned - just a reference)
    uint32_t* trimmed_hash;  // Perfect hash of each line after trimming (collision-free)
    int length;
    bool ignore_whitespace;  // If true, getElement returns hash of trimmed line
} LineSequence;

// Forward declare StringHashMap
typedef struct StringHashMap StringHashMap;

/**
 * Create a LineSequence from array of lines with perfect hash
 * 
 * Uses a hash map to ensure collision-free hashing, matching VSCode's Map<string, number>.
 * The hash_map parameter allows sharing the map across sequences for consistent hashing.
 * 
 * @param lines Array of line strings (must remain valid for lifetime of sequence)
 * @param length Number of lines
 * @param ignore_whitespace If true, trim whitespace before hashing
 * @param hash_map StringHashMap for perfect hashing (can be NULL to create internal map)
 * @return ISequence* that wraps the LineSequence
 * 
 * REUSED BY: Step 1 entry point, Step 2-3 optimization
 * 
 * VSCode Parity: 100% - Perfect hash implementation
 */
ISequence* line_sequence_create(const char** lines, int length, bool ignore_whitespace,
                               StringHashMap* hash_map);

/**
 * CharSequence - Sequence of characters with line boundary tracking
 * 
 * Implements ISequence for character-level diffing within line ranges.
 * Tracks line boundaries to enable proper position translation.
 * 
 * REUSED BY: Step 4 (character refinement)
 * 
 * VSCode Reference: src/vs/editor/common/diff/defaultLinesDiffComputer/linesSliceCharSequence.ts
 */
typedef struct {
    uint32_t* elements;              // Character codes (trimmed if !consider_whitespace)
    int length;                      // Length of elements array
    int* line_start_offsets;         // Offset where each line starts in elements array
    int* trimmed_ws_lengths;         // Leading whitespace trimmed from each line (0 if consider_whitespace)
    int* original_line_start_cols;   // Starting column in original line for each line
    int line_count;                  // Number of lines tracked
    bool consider_whitespace;        // If false, whitespace is trimmed before diffing
} CharSequence;

/**
 * Create a CharSequence from line range
 * 
 * Concatenates lines from [start_line, end_line) range with '\n' separators,
 * tracking line boundaries for position translation.
 * 
 * @param lines Array of line strings
 * @param start_line Start line index (inclusive, 0-based)
 * @param end_line End line index (exclusive, 0-based)
 * @param consider_whitespace If false, trim whitespace before creating sequence
 * @return ISequence* that wraps the CharSequence
 * 
 * REUSED BY: Step 4 (character refinement for each line diff)
 */
ISequence* char_sequence_create(const char** lines, int start_line, int end_line, 
                                bool consider_whitespace);

/**
 * Translate character offset to (line, column) position
 * 
 * Used by Step 4 to convert character-level SequenceDiff offsets
 * back to (line, column) positions for RangeMapping.
 * 
 * @param seq CharSequence (cast from ISequence)
 * @param offset Character offset in the sequence
 * @param out_line Output: 0-based line number
 * @param out_col Output: 0-based column number
 * 
 * REUSED BY: Step 4 (char_level.c) when building RangeMapping
 */
void char_sequence_translate_offset(const CharSequence* seq, int offset, 
                                    int* out_line, int* out_col);

/**
 * Find word containing the given offset - VSCode Parity
 * 
 * Returns the range of the word (alphanumeric characters) that contains
 * the character at the given offset.
 * 
 * VSCode: LinesSliceCharSequence.findWordContaining()
 * 
 * @param seq CharSequence
 * @param offset Character offset
 * @param out_start Output: Start offset of word (inclusive)
 * @param out_end Output: End offset of word (exclusive)
 * @return true if word found, false if offset is not in a word
 */
bool char_sequence_find_word_containing(const CharSequence* seq, int offset,
                                       int* out_start, int* out_end);

/**
 * Find subword containing the given offset - VSCode Parity
 * 
 * Returns the range of the subword (for CamelCase) that contains
 * the character at the given offset. Used for extendToSubwords option.
 * 
 * VSCode: LinesSliceCharSequence.findSubWordContaining()
 * 
 * @param seq CharSequence  
 * @param offset Character offset
 * @param out_start Output: Start offset of subword (inclusive)
 * @param out_end Output: End offset of subword (exclusive)
 * @return true if subword found, false if offset is not in a word
 */
bool char_sequence_find_subword_containing(const CharSequence* seq, int offset,
                                          int* out_start, int* out_end);

/**
 * Count number of lines in character range - VSCode Parity
 * 
 * VSCode: LinesSliceCharSequence.countLinesIn()
 * 
 * @param seq CharSequence
 * @param start_offset Start of range (inclusive)
 * @param end_offset End of range (exclusive)
 * @return Number of lines spanned by the range
 */
int char_sequence_count_lines_in(const CharSequence* seq, int start_offset, int end_offset);

/**
 * Get text for character range - VSCode Parity
 * 
 * VSCode: LinesSliceCharSequence.getText()
 * 
 * @param seq CharSequence
 * @param start_offset Start of range (inclusive)
 * @param end_offset End of range (exclusive)
 * @return Newly allocated string (caller must free), or NULL on error
 */
char* char_sequence_get_text(const CharSequence* seq, int start_offset, int end_offset);

/**
 * Extend range to full lines - VSCode Parity
 * 
 * Extends the given character range to include full lines.
 * 
 * VSCode: LinesSliceCharSequence.extendToFullLines()
 * 
 * @param seq CharSequence
 * @param start_offset Start of range (inclusive)
 * @param end_offset End of range (exclusive)
 * @param out_start Output: Extended start offset
 * @param out_end Output: Extended end offset
 */
void char_sequence_extend_to_full_lines(const CharSequence* seq, 
                                       int start_offset, int end_offset,
                                       int* out_start, int* out_end);

#endif // SEQUENCE_H
