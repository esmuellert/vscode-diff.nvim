#ifndef DIFF_CORE_H
#define DIFF_CORE_H

#include <stdint.h>
#include <stdbool.h>

// ============================================================================
// Data Structures (Based on VSCode's rangeMapping.ts)
// ============================================================================

/**
 * Represents a range of characters within a line.
 * Maps to VSCode's Range class.
 */
typedef struct {
    int start_line;     // 1-indexed line number
    int start_col;      // 1-indexed column number
    int end_line;       // 1-indexed line number
    int end_col;        // 1-indexed column number (exclusive)
} CharRange;

/**
 * Represents a range of lines.
 * Maps to VSCode's LineRange class.
 */
typedef struct {
    int start_line;     // 1-indexed, inclusive
    int end_line;       // 1-indexed, exclusive
} LineRange;

/**
 * Character-level range mapping (innerChanges).
 * Maps to VSCode's RangeMapping class.
 */
typedef struct {
    CharRange original;
    CharRange modified;
} RangeMapping;

/**
 * Highlight type for rendering.
 * Based on VSCode's decoration types in registrations.contribution.ts
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
 * Maps to VSCode's DetailedLineRangeMapping array output.
 */
typedef struct {
    SideRenderPlan left;   // Original/left buffer
    SideRenderPlan right;  // Modified/right buffer
} RenderPlan;

// ============================================================================
// Public API
// ============================================================================

/**
 * Compute diff and generate render plan.
 * 
 * @param lines_a Array of strings (original/left)
 * @param count_a Number of lines in lines_a
 * @param lines_b Array of strings (modified/right)
 * @param count_b Number of lines in lines_b
 * @return RenderPlan* Allocated render plan (caller must free with free_render_plan)
 */
RenderPlan* compute_diff(const char** lines_a, int count_a,
                         const char** lines_b, int count_b);

/**
 * Free a render plan and all its allocated memory.
 */
void free_render_plan(RenderPlan* plan);

/**
 * Get version string.
 */
const char* get_version(void);

/**
 * Enable/disable verbose debug output.
 */
void diff_core_set_verbose(bool enabled);

/**
 * Print render plan details (for debugging).
 */
void diff_core_print_render_plan(const RenderPlan* plan);

#endif // DIFF_CORE_H
