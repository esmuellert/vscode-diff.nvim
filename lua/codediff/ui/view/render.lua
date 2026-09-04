-- Diff computation and rendering for diff view
local M = {}

local core = require("codediff.ui.core")
local semantic = require("codediff.ui.semantic_tokens")
local config = require("codediff.config")
local diff_module = require("codediff.core.diff")

--- Establish scroll synchronization between the two diff windows.
--- Positions each pane's cursor on its own hunk line, then binds them with the
--- structural virtual-row scroll-sync (see codediff.scrollsync) and aligns the
--- original pane to the modified (primary) pane. Replaces native scrollbind so
--- a full-screen filler block no longer causes scroll flicker.
--- @param orig_win number
--- @param mod_win number
--- @param orig_buf number  (unused; kept for call-site compatibility)
--- @param mod_buf number   (unused; kept for call-site compatibility)
--- @param lines_diff table (unused; alignment is derived from placed fillers)
--- @param orig_cursor table|nil: {line, col} on original side
--- @param mod_cursor table|nil: {line, col} on modified side
function M.establish_scrollbind(orig_win, mod_win, orig_buf, mod_buf, lines_diff, orig_cursor, mod_cursor)
  local scroll = require("codediff.ui.scroll")
  local tabpage = vim.api.nvim_win_get_tabpage(mod_win)

  -- Place cursors on their respective hunk lines (per-pane coordinates).
  if orig_cursor then
    pcall(vim.api.nvim_win_set_cursor, orig_win, orig_cursor)
  end
  if mod_cursor then
    pcall(vim.api.nvim_win_set_cursor, mod_win, mod_cursor)
  end

  -- Bind the two panes and align the original pane to the modified pane.
  scroll.bind(tabpage, { orig_win, mod_win })
  scroll.resync(tabpage, mod_win)
end

-- Common logic: Compute diff and render highlights
-- @param auto_scroll_to_first_hunk boolean: Whether to auto-scroll to first change (default true)
-- @param line_range table?: Optional {start_line, end_line} to scroll to instead of first hunk
function M.compute_and_render(
  original_buf,
  modified_buf,
  original_lines,
  modified_lines,
  original_is_virtual,
  modified_is_virtual,
  original_win,
  modified_win,
  auto_scroll_to_first_hunk,
  line_range
)
  -- Compute diff
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

  -- Render diff highlights
  core.render_diff(original_buf, modified_buf, original_lines, modified_lines, lines_diff)

  -- Apply semantic tokens for virtual buffers
  if original_is_virtual then
    semantic.apply_semantic_tokens(original_buf, modified_buf)
  end
  if modified_is_virtual then
    semantic.apply_semantic_tokens(modified_buf, original_buf)
  end

  -- Setup scroll synchronization (only if windows provided)
  if original_win and modified_win and vim.api.nvim_win_is_valid(original_win) and vim.api.nvim_win_is_valid(modified_win) then
    -- Save cursor position if we need to preserve it (on update)
    local saved_cursor = nil
    if not auto_scroll_to_first_hunk then
      saved_cursor = vim.api.nvim_win_get_cursor(modified_win)
    end

    -- Step 1: Ensure native scrollbind is off (replaced by structural sync) and disable wrap
    vim.wo[original_win].scrollbind = false
    vim.wo[modified_win].scrollbind = false
    vim.wo[original_win].wrap = false
    vim.wo[modified_win].wrap = false

    -- Step 2: Determine target cursor positions.
    -- The two panes show different content, so original/modified line
    -- numbers for the same hunk diverge whenever there are insertions or
    -- deletions before it. Use per-pane coordinates (matches the
    -- ui/view/navigation.lua next_hunk/prev_hunk convention).
    local orig_cursor, mod_cursor
    if auto_scroll_to_first_hunk and #lines_diff.changes > 0 then
      -- Honor session.pending_cursor_landing (set by the cycle-hunks-across-
      -- files navigation path; see ui/view/navigation.lua). It's a one-shot
      -- intent — read and clear here so the next render doesn't reapply it.
      -- Look up the session by the modified window's tabpage rather than
      -- find_tabpage_by_buffer (the session's bufnrs are updated AFTER
      -- this render in the file-switch path) or current tabpage (this code
      -- can run from a scheduled callback on a different tab).
      local lifecycle = require("codediff.ui.lifecycle")
      local tabpage = (modified_win and vim.api.nvim_win_is_valid(modified_win)) and vim.api.nvim_win_get_tabpage(modified_win) or nil
      local session = tabpage and lifecycle.get_session(tabpage) or nil
      local landing = session and session.pending_cursor_landing
      if session then
        session.pending_cursor_landing = nil
      end

      if line_range then
        -- Range mode: find the first hunk overlapping the line range, then
        -- use original-side coords for that hunk on both panes (line_range
        -- itself is original-side input from history mode).
        local target_line
        local range_start, range_end = line_range[1], line_range[2]
        for _, change in ipairs(lines_diff.changes) do
          local hunk_start = change.original.start_line
          local hunk_end = change.original.end_line
          if hunk_end >= range_start and hunk_start <= range_end then
            target_line = hunk_start
            break
          end
        end
        if not target_line then
          target_line = range_start
        end
        orig_cursor = { target_line, 0 }
        mod_cursor = { target_line, 0 }
      else
        local hunk = landing == "last" and lines_diff.changes[#lines_diff.changes] or lines_diff.changes[1]
        orig_cursor = { hunk.original.start_line, 0 }
        mod_cursor = { hunk.modified.start_line, 0 }
      end
    elseif saved_cursor then
      orig_cursor = { saved_cursor[1], 0 }
      mod_cursor = saved_cursor
    else
      orig_cursor = { 1, 0 }
      mod_cursor = { 1, 0 }
    end

    -- Step 3: Position cursors and bind the structural scroll-sync
    M.establish_scrollbind(original_win, modified_win, original_buf, modified_buf, lines_diff, orig_cursor, mod_cursor)

    -- Step 4: Center view on first hunk for initial open
    if auto_scroll_to_first_hunk and #lines_diff.changes > 0 then
      if vim.api.nvim_win_is_valid(modified_win) then
        vim.api.nvim_set_current_win(modified_win)
        vim.cmd("normal! zz")
      end
    end
  end

  return lines_diff
end

-- Common logic: Setup auto-refresh for all diff buffers (real and virtual)
function M.setup_auto_refresh(original_buf, modified_buf, original_is_virtual, modified_is_virtual)
  local auto_refresh = require("codediff.ui.auto_refresh")
  auto_refresh.enable(original_buf)
  auto_refresh.enable(modified_buf)
end

return M
