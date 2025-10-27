#ifndef DIFF_TYPES_H
#define DIFF_TYPES_H

#include <stdint.h>
#include <stdbool.h>

// ============================================================================
// INTERMEDIATE DATA STRUCTURES (Algorithm Pipeline)
// ============================================================================

/**
 * SequenceDiff - Output from Myers algorithm
 * Represents a difference region between two sequences.
 */
typedef struct {
    int seq1_start;      // Start index in sequence 1 (0-indexed)
    int seq1_end;        // End index in sequence 1 (exclusive)
    int seq2_start;      // Start index in sequence 2 (0-indexed)
    int seq2_end;        // End index in sequence 2 (exclusive)
} SequenceDiff;

typedef struct {
    SequenceDiff* diffs;
    int count;
    int capacity;
} SequenceDiffArray;

/**
 * Timeout - Timeout mechanism for diff computation
 * Maps to VSCode's ITimeout interface.
 */
typedef struct {
    int timeout_ms;         // Timeout in milliseconds (0 = infinite)
    int64_t start_time_ms;  // Start time in milliseconds
} Timeout;

/**
 * CharRange - Represents a range of characters within text
 * Maps to VSCode's Range class.
 */
typedef struct {
    int start_line;     // 1-indexed line number
    int start_col;      // 1-indexed column number
    int end_line;       // 1-indexed line number
    int end_col;        // 1-indexed column number (exclusive)
} CharRange;

/**
 * LineRange - Represents a range of lines
 * Maps to VSCode's LineRange class.
 */
typedef struct {
    int start_line;     // 1-indexed, inclusive
    int end_line;       // 1-indexed, exclusive
} LineRange;

/**
 * RangeMapping - Character-level range mapping
 * Maps to VSCode's RangeMapping class.
 * Output from character-level diff (Step 4).
 */
typedef struct {
    CharRange original;
    CharRange modified;
} RangeMapping;

typedef struct {
    RangeMapping* mappings;
    int count;
    int capacity;
} RangeMappingArray;

/**
 * DetailedLineRangeMapping - Final algorithm output
 * Maps to VSCode's DetailedLineRangeMapping.
 * Combines line-level diff with character-level details.
 */
typedef struct {
    LineRange original;          // Which lines in original
    LineRange modified;          // Which lines in modified
    RangeMapping* inner_changes; // Character-level changes (NULL if no inner changes)
    int inner_change_count;      // Number of inner changes
} DetailedLineRangeMapping;

typedef struct {
    DetailedLineRangeMapping* mappings;
    int count;
    int capacity;
} DetailedLineRangeMappingArray;

/**
 * MovedText - Represents moved code blocks
 * Maps to VSCode's MovedText.
 */
typedef struct {
    LineRange original;
    LineRange modified;
} MovedText;

typedef struct {
    MovedText* moves;
    int count;
    int capacity;
} MovedTextArray;

/**
 * DiffOptions - Configuration for diff computation
 * Maps to VSCode's ILinesDiffComputerOptions.
 */
typedef struct {
    bool ignore_trim_whitespace;   // If true, ignore leading/trailing whitespace
    int max_computation_time_ms;   // 0 = infinite timeout
    bool compute_moves;            // If true, compute moved blocks (not implemented yet)
    bool extend_to_subwords;       // If true, extend diffs to subword boundaries
} DiffOptions;

/**
 * LinesDiff - Complete algorithm output
 * Maps to VSCode's LinesDiff interface.
 */
typedef struct {
    DetailedLineRangeMappingArray changes;
    MovedTextArray moves;
    bool hit_timeout;
} LinesDiff;

// ============================================================================
// RENDER DATA STRUCTURES (For UI)
// ============================================================================

/**
 * Highlight type for rendering.
 * Based on VSCode's decoration types.
 */
typedef enum {
    HL_LINE_INSERT = 0,  // Light green background (entire line)
    HL_LINE_DELETE = 1,  // Light red background (entire line)
    HL_CHAR_INSERT = 2,  // Deep/dark green (changed characters only)
    HL_CHAR_DELETE = 3   // Deep/dark red (changed characters only)
} HighlightType;

/**
 * Character-level highlight region.
 */
typedef struct {
    int line_num;       // 1-indexed line number in buffer
    int start_col;      // 1-indexed column (inclusive)
    int end_col;        // 1-indexed column (exclusive)
    HighlightType type;
} CharHighlight;

/**
 * Line-level metadata for rendering.
 */
typedef struct {
    int line_num;           // 1-indexed line number in buffer
    HighlightType type;     // Line-level highlight type (INSERT or DELETE)
    bool is_filler;         // True if this is a filler/virtual line
    int char_highlight_count;
    CharHighlight* char_highlights;  // Array of character-level highlights
} LineMetadata;

/**
 * Render plan for one side (left/original or right/modified).
 */
typedef struct {
    int line_count;
    LineMetadata* line_metadata;  // Array of line_count elements
} SideRenderPlan;

/**
 * Complete render plan for diff view.
 * This is what gets passed to the Lua rendering layer.
 */
typedef struct {
    SideRenderPlan left;   // Original/left buffer
    SideRenderPlan right;  // Modified/right buffer
} RenderPlan;

#endif // DIFF_TYPES_H
