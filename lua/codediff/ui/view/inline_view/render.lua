-- Diff computation and rendering for inline views.
local M = {}

local lifecycle = require("codediff.ui.lifecycle")
local config = require("codediff.config")
local diff_module = require("codediff.core.diff")
local inline = require("codediff.ui.inline")
local semantic = require("codediff.ui.semantic_tokens")
local cursor_util = require("codediff.ui.view.cursor")

function M.compute_and_render_inline(modified_buf, original_buf, original_lines, modified_lines, original_is_virtual, modified_is_virtual, modified_win, auto_scroll_to_first_hunk)
  local diff_options = {
    max_computation_time_ms = config.options.diff.max_computation_time_ms,
    ignore_trim_whitespace = config.options.diff.ignore_trim_whitespace,
    compute_moves = config.options.diff.compute_moves,
  }

  local lines_diff = diff_module.compute_diff(original_lines, modified_lines, diff_options)
  if not lines_diff then
    vim.notify("Failed to compute diff", vim.log.levels.ERROR)
    return nil
  end

  inline.render_inline_diff(modified_buf, lines_diff, original_lines, modified_lines)

  if original_is_virtual then
    semantic.apply_semantic_tokens(original_buf, modified_buf)
  end
  if modified_is_virtual then
    semantic.apply_semantic_tokens(modified_buf, original_buf)
  end

  if modified_win and vim.api.nvim_win_is_valid(modified_win) then
    vim.wo[modified_win].wrap = false
    if auto_scroll_to_first_hunk and lines_diff.changes and #lines_diff.changes > 0 then
      -- Honor session.pending_cursor_landing (cycle-hunks-across-files
      -- backward direction sets it to "last"; see ui/view/navigation.lua).
      -- Look up the session via the window's tabpage because this code can
      -- run from a scheduled callback on a different tab.
      local lifecycle = require("codediff.ui.lifecycle")
      local tabpage = vim.api.nvim_win_get_tabpage(modified_win)
      local session = tabpage and lifecycle.get_session(tabpage) or nil
      local landing = session and session.pending_cursor_landing
      if session then
        session.pending_cursor_landing = nil
      end

      local target_line = landing == "last" and lines_diff.changes[#lines_diff.changes].modified.start_line or lines_diff.changes[1].modified.start_line
      target_line = cursor_util.clamp_window_line(modified_win, target_line)
      pcall(vim.api.nvim_win_set_cursor, modified_win, { target_line, 0 })
      vim.api.nvim_set_current_win(modified_win)
      vim.cmd("normal! zz")
    end
  end

  return lines_diff
end

function M.rerender(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session or session.layout ~= "inline" then
    return
  end

  local original_bufnr = session.original_bufnr
  local modified_bufnr = session.modified_bufnr

  if not vim.api.nvim_buf_is_valid(original_bufnr) or not vim.api.nvim_buf_is_valid(modified_bufnr) then
    return
  end

  local original_lines = vim.api.nvim_buf_get_lines(original_bufnr, 0, -1, false)
  local modified_lines = vim.api.nvim_buf_get_lines(modified_bufnr, 0, -1, false)

  local diff_options = {
    max_computation_time_ms = config.options.diff.max_computation_time_ms,
    ignore_trim_whitespace = config.options.diff.ignore_trim_whitespace,
    compute_moves = config.options.diff.compute_moves,
  }

  local lines_diff = diff_module.compute_diff(original_lines, modified_lines, diff_options)
  if lines_diff then
    inline.render_inline_diff(modified_bufnr, lines_diff, original_lines, modified_lines)
    lifecycle.update_diff_result(tabpage, lines_diff)
  end
end

return M
