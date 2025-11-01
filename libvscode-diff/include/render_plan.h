#ifndef RENDER_PLAN_H
#define RENDER_PLAN_H

#include "types.h"

/**
 * Generate render plan from LinesDiff result.
 * 
 * Converts the algorithmic diff output (LinesDiff with DetailedLineRangeMapping)
 * into a render plan suitable for Neovim UI visualization.
 * 
 * The render plan contains:
 * - Line-level highlights (entire line as insert/delete)
 * - Character-level highlights (precise character ranges)
 * - Filler line information for alignment
 * 
 * @param diff LinesDiff from compute_diff()
 * @param original_lines Original file lines
 * @param original_count Number of lines in original
 * @param modified_lines Modified file lines
 * @param modified_count Number of lines in modified
 * @return RenderPlan (caller must free with free_render_plan())
 */
RenderPlan* generate_render_plan(
    const LinesDiff* diff,
    const char** original_lines,
    int original_count,
    const char** modified_lines,
    int modified_count
);

/**
 * Free render plan and all contained data.
 * 
 * @param plan RenderPlan to free (can be NULL)
 */
void free_render_plan(RenderPlan* plan);

#endif // RENDER_PLAN_H
