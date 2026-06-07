-- Compact mode: fold unchanged regions, showing only hunks + context lines
local M = {}

local lifecycle = require("codediff.ui.lifecycle")
local config = require("codediff.config")

-- Module-level state: maps window ID → set of visible line numbers
local visible_lines_by_win = {}

-- Recursion guard for fold sync: when we propagate a fold action from pane A
-- to pane B, the propagated action would otherwise fire pane B's wrapper and
-- bounce back. Set true while a sync is in flight.
local _syncing = false

--- Called by Neovim for each line when foldmethod=expr
--- @return string fold level: "0" for visible lines, "1" for foldable
function M.foldexpr_eval()
  local visible = visible_lines_by_win[vim.api.nvim_get_current_win()]
  if not visible then
    return "0"
  end
  return visible[vim.v.lnum] and "0" or "1"
end

--- Map a line number from one side of the diff to the corresponding line on
--- the other side. Mirrors Neovim's native diff_lnum_win used by C-level
--- setManualFold for diff-mode fold sync (src/nvim/fold.c).
---
--- Each change in `changes` maps original.[start, end) to modified.[start, end).
--- Between changes the offset is constant; inside a change it grows linearly.
--- @param changes table[]
--- @param from_side "original"|"modified"
--- @param to_side "original"|"modified"
--- @param lnum number 1-based source line
--- @return number 1-based target line
function M.compute_corresponding_lnum(changes, from_side, to_side, lnum)
  if from_side == to_side then
    return lnum
  end
  local delta = 0
  for _, change in ipairs(changes or {}) do
    local from = change[from_side]
    local to = change[to_side]
    if lnum < from.start_line then
      -- before this change; accumulated delta already correct
      break
    end
    if lnum < from.end_line then
      -- inside this change's source range — clamp to corresponding range
      local from_len = from.end_line - from.start_line
      local to_len = to.end_line - to.start_line
      if from_len == 0 then
        return to.start_line
      end
      -- Proportional map; if to_len == 0 we still get to.start_line.
      local offset = lnum - from.start_line
      local target = to.start_line + math.floor(offset * to_len / from_len)
      if target >= to.end_line then
        target = math.max(to.start_line, to.end_line - 1)
      end
      return target
    end
    -- past this change; update running delta
    delta = (to.end_line - from.end_line)
  end
  return lnum + delta
end

--- Compute set of line numbers that should remain visible (near hunks)
--- @param changes table[] array of hunk mappings with original/modified ranges
--- @param side string "original" or "modified"
--- @param line_count number total lines in buffer
--- @param context_lines number lines of context around each hunk
--- @return table<number, boolean> set of 1-indexed visible line numbers
function M.compute_visible_lines(changes, side, line_count, context_lines)
  local visible = {}
  for _, change in ipairs(changes) do
    local range = change[side]
    local range_start = range.start_line
    local range_end = range.end_line -- exclusive

    -- For zero-width ranges (pure insertion/deletion), use start_line as anchor
    if range_start == range_end then
      range_end = range_start + 1
    end

    local ctx_start = math.max(1, range_start - context_lines)
    local ctx_end = math.min(line_count, range_end - 1 + context_lines)
    for l = ctx_start, ctx_end do
      visible[l] = true
    end
  end
  return visible
end

-- Keys whose action is "open/close folds at cursor". Mirrors the set that
-- Neovim's setManualFold runs the diff-sync loop for (anything that opens or
-- closes folds — navigation keys like zj/zk/]z/[z are excluded since they
-- don't change fold state).
local FOLD_KEYS = {
  "zo", "zO", "zc", "zC", "za", "zA", "zv", "zx", "zX", "zM", "zR",
}

--- Install buffer-local keymap wraps that propagate fold-open/close actions
--- to the partner pane. Mirrors the algorithm in Neovim's setManualFold:
---
---   1. apply the fold action in the current window (default behavior)
---   2. for every other diff pane, map cursor lnum to that pane's coords
---   3. apply the same fold action in that pane
---
--- @param session table
local function setup_fold_sync(session)
  if session.layout == "inline" then
    return -- single pane, nothing to sync
  end
  if not config.options.diff.compact_sync_folds then
    return
  end

  local panes = {
    { win = session.original_win, buf = session.original_bufnr, side = "original" },
    { win = session.modified_win, buf = session.modified_bufnr, side = "modified" },
  }

  for _, pane in ipairs(panes) do
    if pane.win and vim.api.nvim_win_is_valid(pane.win)
        and pane.buf and vim.api.nvim_buf_is_valid(pane.buf) then
      for _, key in ipairs(FOLD_KEYS) do
        vim.keymap.set("n", key, function()
          local count = vim.v.count > 0 and tostring(vim.v.count) or ""
          -- 1. Apply the fold action locally.
          vim.cmd("normal! " .. count .. key)

          -- 2. Skip propagation if we are inside a sync triggered by the
          --    partner pane (prevents reentry through autocmds).
          if _syncing then
            return
          end

          local s = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
          if not s or not s.compact_mode then
            return
          end
          local changes = s.stored_diff_result and s.stored_diff_result.changes
          if not changes or #changes == 0 then
            return
          end

          local src_lnum = vim.api.nvim_win_get_cursor(0)[1]
          _syncing = true
          local ok, err = pcall(function()
            for _, other in ipairs(panes) do
              if other.win ~= pane.win
                  and other.win and vim.api.nvim_win_is_valid(other.win) then
                local target = M.compute_corresponding_lnum(changes, pane.side, other.side, src_lnum)
                target = math.max(1, math.min(target, vim.api.nvim_buf_line_count(other.buf)))
                -- Save & restore cursor so the partner pane doesn't visibly jump.
                local saved_cursor = vim.api.nvim_win_get_cursor(other.win)
                vim.api.nvim_win_call(other.win, function()
                  vim.api.nvim_win_set_cursor(other.win, { target, 0 })
                  vim.cmd("normal! " .. key)
                end)
                pcall(vim.api.nvim_win_set_cursor, other.win, saved_cursor)
              end
            end
          end)
          _syncing = false
          if not ok then
            vim.notify("[codediff] synced-fold error: " .. tostring(err), vim.log.levels.DEBUG)
          end
        end, { buffer = pane.buf, silent = true, desc = "codediff: synced fold " .. key })
      end
    end
  end
end

--- Remove the synced-fold keymap wraps from a session's panes.
--- Buffer-local keymaps usually die with the buffer, but for the conflict /
--- explorer paths where buffers persist we need to delete explicitly.
--- @param session table
local function teardown_fold_sync(session)
  local panes = { session.original_bufnr, session.modified_bufnr }
  for _, buf in ipairs(panes) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      for _, key in ipairs(FOLD_KEYS) do
        pcall(vim.keymap.del, "n", key, { buffer = buf })
      end
    end
  end
end

--- Enable compact mode for a tabpage
--- @param tabpage number
--- @return boolean success
function M.enable(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session or not session.stored_diff_result then
    return false
  end
  if session.compact_mode then
    return true
  end
  if session.result_win and vim.api.nvim_win_is_valid(session.result_win) then
    vim.notify("Cannot enable compact mode in conflict mode", vim.log.levels.WARN)
    return false
  end

  local changes = session.stored_diff_result.changes
  if not changes or #changes == 0 then
    vim.notify("No changes to compact", vim.log.levels.INFO)
    return false
  end

  local context = config.options.diff.compact_context_lines

  -- Determine which windows to fold
  local entries = {}
  if session.layout == "inline" then
    table.insert(entries, { win = session.modified_win, buf = session.modified_bufnr, side = "modified" })
  else
    table.insert(entries, { win = session.original_win, buf = session.original_bufnr, side = "original" })
    table.insert(entries, { win = session.modified_win, buf = session.modified_bufnr, side = "modified" })
  end

  session.compact_saved_fold_state = {}

  for _, entry in ipairs(entries) do
    if entry.win and vim.api.nvim_win_is_valid(entry.win) then
      -- Save current fold state
      session.compact_saved_fold_state[entry.win] = {
        foldmethod = vim.wo[entry.win].foldmethod,
        foldexpr = vim.wo[entry.win].foldexpr,
        foldlevel = vim.wo[entry.win].foldlevel,
        foldminlines = vim.wo[entry.win].foldminlines,
        foldenable = vim.wo[entry.win].foldenable,
        foldtext = vim.wo[entry.win].foldtext,
      }

      -- Compute visible lines
      local line_count = vim.api.nvim_buf_line_count(entry.buf)
      visible_lines_by_win[entry.win] = M.compute_visible_lines(changes, entry.side, line_count, context)

      -- Apply fold settings
      vim.wo[entry.win].foldmethod = "expr"
      vim.wo[entry.win].foldexpr = "v:lua.require'codediff.ui.view.compact'.foldexpr_eval()"
      vim.wo[entry.win].foldenable = true
      vim.wo[entry.win].foldlevel = 0
      vim.wo[entry.win].foldminlines = 1
    end
  end

  session.compact_mode = true
  setup_fold_sync(session)
  return true
end

--- Disable compact mode for a tabpage
--- @param tabpage number
--- @return boolean success
function M.disable(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session or not session.compact_mode then
    return false
  end

  local saved = session.compact_saved_fold_state or {}
  for win, fold_state in pairs(saved) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].foldmethod = fold_state.foldmethod
      vim.wo[win].foldexpr = fold_state.foldexpr
      vim.wo[win].foldlevel = fold_state.foldlevel
      vim.wo[win].foldminlines = fold_state.foldminlines
      vim.wo[win].foldenable = fold_state.foldenable
      vim.wo[win].foldtext = fold_state.foldtext
    end
    visible_lines_by_win[win] = nil
  end

  teardown_fold_sync(session)

  session.compact_saved_fold_state = nil
  session.compact_mode = false
  return true
end

--- Toggle compact mode
--- @param tabpage? number defaults to current tabpage
--- @return boolean success
function M.toggle(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local session = lifecycle.get_session(tabpage)
  if not session then
    return false
  end

  if session.compact_mode then
    return M.disable(tabpage)
  else
    return M.enable(tabpage)
  end
end

--- Re-apply compact mode fold settings to current windows.
--- Called after file switches or re-renders where window buffers change
--- but session.compact_mode should persist.
--- @param tabpage number
function M.reapply(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session or not session.compact_mode then
    return
  end
  if not session.stored_diff_result then
    return
  end

  local changes = session.stored_diff_result.changes
  if not changes or #changes == 0 then
    return
  end

  local context = config.options.diff.compact_context_lines

  local entries = {}
  if session.layout == "inline" then
    table.insert(entries, { win = session.modified_win, buf = session.modified_bufnr, side = "modified" })
  else
    table.insert(entries, { win = session.original_win, buf = session.original_bufnr, side = "original" })
    table.insert(entries, { win = session.modified_win, buf = session.modified_bufnr, side = "modified" })
  end

  for _, entry in ipairs(entries) do
    if entry.win and vim.api.nvim_win_is_valid(entry.win) then
      local line_count = vim.api.nvim_buf_line_count(entry.buf)
      visible_lines_by_win[entry.win] = M.compute_visible_lines(changes, entry.side, line_count, context)

      vim.wo[entry.win].foldmethod = "expr"
      vim.wo[entry.win].foldexpr = "v:lua.require'codediff.ui.view.compact'.foldexpr_eval()"
      vim.wo[entry.win].foldenable = true
      vim.wo[entry.win].foldlevel = 0
      vim.wo[entry.win].foldminlines = 1
    end
  end

  -- Buffers may have changed (file switch in explorer mode). Re-install
  -- the sync keymaps on the current bufnrs.
  setup_fold_sync(session)
end

--- Refresh compact mode after diff recomputation.
--- Re-applies fold settings and forces fold re-evaluation.
--- @param tabpage number
function M.refresh(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session or not session.compact_mode then
    return
  end

  local changes = session.stored_diff_result and session.stored_diff_result.changes
  if not changes or #changes == 0 then
    M.disable(tabpage)
    return
  end

  M.reapply(tabpage)
end

return M
