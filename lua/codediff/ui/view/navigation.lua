-- Navigation module - provides public API for navigating hunks and files
local M = {}

local lifecycle = require("codediff.ui.lifecycle")
local config = require("codediff.config")

-- Navigate to next hunk in the current diff view
-- Returns true if navigation succeeded, false otherwise
function M.next_hunk()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local session = lifecycle.get_session(tabpage)
  if not session or not session.stored_diff_result then
    return false
  end

  local diff_result = session.stored_diff_result
  if not diff_result.changes or #diff_result.changes == 0 then
    return false
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local original_bufnr = session.original_bufnr
  local modified_bufnr = session.modified_bufnr
  local is_inline = session.layout == "inline"

  local is_original = current_buf == original_bufnr
  local is_modified = current_buf == modified_bufnr
  local is_result = session.result_bufnr and current_buf == session.result_bufnr

  -- Inline mode: always use modified line numbers
  if is_inline then
    is_original = false
  -- If cursor is in result buffer (conflict mode), use modified side line numbers
  elseif is_result then
    is_original = false
  -- If cursor is not in any diff buffer, switch to modified window
  elseif not is_original and not is_modified then
    is_original = false
    local target_win = session.modified_win
    if target_win and vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_set_current_win(target_win)
    else
      return false
    end
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Find next hunk after current line
  for i, mapping in ipairs(diff_result.changes) do
    local target_line = is_original and mapping.original.start_line or mapping.modified.start_line
    if target_line > current_line then
      pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
      vim.cmd("normal! zz")
      vim.api.nvim_echo({ { string.format("Hunk %d of %d", i, #diff_result.changes), "None" } }, false, {})
      return true
    end
  end

  -- Wrap around to first hunk (if cycling enabled)
  if config.options.diff.cycle_next_hunk then
    local first_hunk = diff_result.changes[1]
    local target_line = is_original and first_hunk.original.start_line or first_hunk.modified.start_line
    pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
    vim.cmd("normal! zz")
    vim.api.nvim_echo({ { string.format("Hunk 1 of %d", #diff_result.changes), "None" } }, false, {})
    return true
  else
    vim.api.nvim_echo({ { string.format("Last hunk (%d of %d)", #diff_result.changes, #diff_result.changes), "WarningMsg" } }, false, {})
    return false
  end
end

-- Navigate to previous hunk in the current diff view
-- Returns true if navigation succeeded, false otherwise
function M.prev_hunk()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local session = lifecycle.get_session(tabpage)
  if not session or not session.stored_diff_result then
    return false
  end

  local diff_result = session.stored_diff_result
  if not diff_result.changes or #diff_result.changes == 0 then
    return false
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local original_bufnr = session.original_bufnr
  local modified_bufnr = session.modified_bufnr
  local is_inline = session.layout == "inline"

  local is_original = current_buf == original_bufnr
  local is_modified = current_buf == modified_bufnr
  local is_result = session.result_bufnr and current_buf == session.result_bufnr

  -- Inline mode: always use modified line numbers
  if is_inline then
    is_original = false
  -- If cursor is in result buffer (conflict mode), use modified side line numbers
  elseif is_result then
    is_original = false
  -- If cursor is not in any diff buffer, switch to modified window
  elseif not is_original and not is_modified then
    is_original = false
    local target_win = session.modified_win
    if target_win and vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_set_current_win(target_win)
    else
      return false
    end
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  -- Find previous hunk before current line (search backwards)
  for i = #diff_result.changes, 1, -1 do
    local mapping = diff_result.changes[i]
    local target_line = is_original and mapping.original.start_line or mapping.modified.start_line
    if target_line < current_line then
      pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
      vim.cmd("normal! zz")
      vim.api.nvim_echo({ { string.format("Hunk %d of %d", i, #diff_result.changes), "None" } }, false, {})
      return true
    end
  end

  -- Wrap around to last hunk (if cycling enabled)
  if config.options.diff.cycle_next_hunk then
    local last_hunk = diff_result.changes[#diff_result.changes]
    local target_line = is_original and last_hunk.original.start_line or last_hunk.modified.start_line
    pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
    vim.cmd("normal! zz")
    vim.api.nvim_echo({ { string.format("Hunk %d of %d", #diff_result.changes, #diff_result.changes), "None" } }, false, {})
    return true
  else
    vim.api.nvim_echo({ { string.format("First hunk (1 of %d)", #diff_result.changes), "WarningMsg" } }, false, {})
    return false
  end
end

-- Navigate to next file in explorer/history mode
-- In single-file history mode, navigates to next commit instead
-- Returns true if navigation succeeded, false otherwise
function M.next_file()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local session = lifecycle.get_session(tabpage)
  local panel_obj = lifecycle.get_explorer(tabpage)

  if not panel_obj then
    return false
  end

  local is_history_mode = session and session.mode == "history"

  if is_history_mode then
    local history = require("codediff.ui.history")
    if panel_obj.is_single_file_mode then
      history.navigate_next_commit(panel_obj)
    else
      history.navigate_next(panel_obj)
    end
  else
    local explorer = require("codediff.ui.explorer")
    explorer.navigate_next(panel_obj)
  end

  return true
end

-- Navigate to previous file in explorer/history mode
-- In single-file history mode, navigates to previous commit instead
-- Returns true if navigation succeeded, false otherwise
function M.prev_file()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local session = lifecycle.get_session(tabpage)
  local panel_obj = lifecycle.get_explorer(tabpage)

  if not panel_obj then
    return false
  end

  local is_history_mode = session and session.mode == "history"

  if is_history_mode then
    local history = require("codediff.ui.history")
    if panel_obj.is_single_file_mode then
      history.navigate_prev_commit(panel_obj)
    else
      history.navigate_prev(panel_obj)
    end
  else
    local explorer = require("codediff.ui.explorer")
    explorer.navigate_prev(panel_obj)
  end

  return true
end

-- Scroll diff windows by half page
-- @param direction "up" or "down"
function M.scroll_diff_windows(direction)
  local tabpage = vim.api.nvim_get_current_tabpage()
  local session = lifecycle.get_session(tabpage)
  if not session then
    return false
  end

  local mod_win = session.modified_win

  if not mod_win or not vim.api.nvim_win_is_valid(mod_win) then
    return false
  end

  -- Map direction to Vim half-page scroll commands
  local scroll_keys = {
    up = "<C-u>",
    down = "<C-d>",
  }

  local scroll_key = scroll_keys[direction]
  if not scroll_key then
    return false
  end

  -- Execute scroll command by temporarily switching to modified window
  -- Scrollbind will automatically sync the original window
  local current_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(mod_win)
  local keys = vim.api.nvim_replace_termcodes(scroll_key, true, false, true)
  vim.api.nvim_feedkeys(keys, "x", false)
  vim.api.nvim_set_current_win(current_win)

  return true
end

return M
