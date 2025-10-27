#ifndef DIFF_API_H
#define DIFF_API_H

#include "types.h"

/**
 * Main API: Compute diff and generate render plan.
 * 
 * This is the primary entry point for Lua/FFI usage. It combines:
 * 1. compute_diff() - VSCode-compatible diff algorithm
 * 2. generate_render_plan() - Convert to Neovim rendering structure
 * 
 * @param original_lines Original file lines
 * @param original_count Number of lines in original
 * @param modified_lines Modified file lines
 * @param modified_count Number of lines in modified
 * @param options Diff computation options
 * @return RenderPlan for Neovim UI (caller must free with free_render_plan())
 * 
 * Usage from Lua:
 *   local ffi = require('ffi')
 *   local lib = ffi.load('libdiff_core.so')
 *   local plan = lib.compute_diff_render_plan(orig_lines, ...)
 *   -- use plan.left/right for visualization
 *   lib.free_render_plan(plan)
 */
RenderPlan* compute_diff_render_plan(
    const char** original_lines,
    int original_count,
    const char** modified_lines,
    int modified_count,
    const DiffOptions* options
);

/**
 * Get library version string.
 * 
 * @return Version string
 */
const char* diff_api_get_version(void);

#endif // DIFF_API_H
