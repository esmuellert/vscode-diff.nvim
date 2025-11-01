// ============================================================================
// Diff API - Main Entry Point
// ============================================================================
// 
// High-level API combining compute_diff and render plan generation.
// This is the primary interface for Lua/FFI callers.
//
// ============================================================================

#include "diff_api.h"
#include "default_lines_diff_computer.h"
#include "render_plan.h"
#include <stdlib.h>

/**
 * Compute diff and generate render plan.
 * 
 * Combines the full pipeline:
 * 1. Line-level diff (Myers or DP)
 * 2. Character-level refinement
 * 3. Whitespace change scanning
 * 4. Render plan generation for Neovim
 * 
 * @param original_lines Original file lines
 * @param original_count Number of lines in original
 * @param modified_lines Modified file lines
 * @param modified_count Number of lines in modified
 * @param options Diff computation options
 * @return RenderPlan (caller must free)
 */
RenderPlan* compute_diff_render_plan(
    const char** original_lines,
    int original_count,
    const char** modified_lines,
    int modified_count,
    const DiffOptions* options
) {
    // Step 1: Compute diff (VSCode-compatible algorithm)
    LinesDiff* diff = compute_diff(
        original_lines, original_count,
        modified_lines, modified_count,
        options
    );
    
    if (!diff) {
        return NULL;
    }
    
    // Step 2: Generate render plan for Neovim
    RenderPlan* plan = generate_render_plan(
        diff,
        original_lines, original_count,
        modified_lines, modified_count
    );
    
    // Cleanup intermediate result
    free_lines_diff(diff);
    
    return plan;
}

/**
 * Get library version.
 */
const char* diff_api_get_version(void) {
    return "0.3.0-full-pipeline";
}
