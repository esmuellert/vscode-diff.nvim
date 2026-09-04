-- vscode-diff main API
local M = {}

-- Configuration setup
function M.setup(opts)
  local config = require("codediff.config")
  config.setup(opts)

  local render = require("codediff.ui")
  render.setup_highlights()
end

-- Navigate to next hunk in the current diff view
-- Returns true if navigation succeeded, false otherwise
function M.next_hunk()
  local navigation = require("codediff.ui.view.navigation")
  return navigation.next_hunk()
end

-- Navigate to previous hunk in the current diff view
-- Returns true if navigation succeeded, false otherwise
function M.prev_hunk()
  local navigation = require("codediff.ui.view.navigation")
  return navigation.prev_hunk()
end

-- Navigate to next file in explorer/history mode
-- In single-file history mode, navigates to next commit instead
-- Returns true if navigation succeeded, false otherwise
function M.next_file()
  local navigation = require("codediff.ui.view.navigation")
  return navigation.next_file()
end

-- Navigate to previous file in explorer/history mode
-- In single-file history mode, navigates to previous commit instead
-- Returns true if navigation succeeded, false otherwise
function M.prev_file()
  local navigation = require("codediff.ui.view.navigation")
  return navigation.prev_file()
end

-- ============================================================================
-- Inline diff public API
-- ============================================================================

-- Compute diff between two sets of lines (pure, no side effects)
-- @param original_lines string[]: reference content
-- @param modified_lines string[]: current content
-- @param opts? table: { ignore_trim_whitespace?: bool, max_computation_time_ms?: int, compute_moves?: bool, extend_to_subwords?: bool }
-- @return table: { changes: table[], moves: table[], hit_timeout: boolean }
function M.diff(original_lines, modified_lines, opts)
  return require("codediff.core.diff").compute_diff(original_lines, modified_lines, opts)
end

-- Render inline diff on a buffer (deleted lines as virtual lines, added lines highlighted)
-- @param bufnr number: buffer to render on (should contain the modified content)
-- @param diff_result table: result from codediff.diff()
-- @param original_lines string[]: reference content (used for virtual line text)
-- @param modified_lines string[]: current buffer content
-- @param opts? table: { filetype?: string }
function M.render_inline_diff(bufnr, diff_result, original_lines, modified_lines, opts)
  return require("codediff.ui.inline").render_inline_diff(bufnr, diff_result, original_lines, modified_lines, opts)
end

-- Clear inline diff decorations from a buffer
-- @param bufnr number: buffer to clear
function M.clear_inline_diff(bufnr)
  return require("codediff.ui.inline").clear(bufnr)
end

-- Toggle inline diff rendering (standalone mode with git integration)
-- @param show nil|bool: nil = toggle, true = show, false = hide
-- @param global bool|nil: if true, applies to all git-tracked buffers
function M.render_inline(show, global)
  local inline_render = require("codediff.ui.inline_render")
  inline_render.toggle(show, global)
end

-- Change the base revision for diff comparison
-- @param base string|nil: revision (e.g. "HEAD", "HEAD~1", "main"), nil = reset to index
-- @param global bool|nil: if true, applies to all buffers
function M.change_base(base, global)
  local inline_render = require("codediff.ui.inline_render")
  inline_render.change_base(base, global)
end

return M
