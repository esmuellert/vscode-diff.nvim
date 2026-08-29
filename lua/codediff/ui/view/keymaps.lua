-- Keymap declarations for the diff view.
--
-- This module decides which keys are bound, on which buffers, in which session
-- shapes. The behavior behind each key lives in ui/view/actions/, and receives
-- the session context below rather than closing over buffers and layout flags,
-- so a mapping cannot act on a buffer the session has since replaced.
local M = {}

local lifecycle = require("codediff.ui.lifecycle")
local config = require("codediff.config")
local resolve = require("codediff.keymap.resolve")
local navigation = require("codediff.ui.view.navigation")
local compact = require("codediff.ui.view.compact")

local hunk = require("codediff.ui.view.actions.hunk")
local diffget = require("codediff.ui.view.actions.diffget")
local panes = require("codediff.ui.view.actions.panes")
local stage = require("codediff.ui.view.actions.stage")
local move = require("codediff.ui.view.actions.move")

--- @class CodeDiffActionContext
--- @field tabpage number
--- @field original_bufnr number
--- @field modified_bufnr number
--- @field is_explorer_mode boolean
--- @field is_history_mode boolean
--- @field is_inline boolean
--- @field is_conflict boolean Merge view: a result pane exists

-- Centralized keymap setup for all diff view keymaps
-- This function sets up ALL keymaps in one place for better maintainability
function M.setup_all_keymaps(tabpage, original_bufnr, modified_bufnr, is_explorer_mode)
  -- Scope the pass so mappings from a previous session shape (gm after
  -- switching to inline, an old quit key after reconfiguration) are retired
  -- rather than left installed alongside the new ones.
  lifecycle.begin_keymap_scope(tabpage, "view")

  local keymaps = resolve.keymaps_for("view")

  -- Check mode context
  local session = lifecycle.get_session(tabpage)
  local is_history_mode = session and session.panel ~= nil and session.panel.name == "history"
  local is_inline = session and session.layout == "inline"
  -- Merge/conflict view: do/dp are replaced by the conflict mappings (see
  -- codediff.ui.conflict.keymaps). Read the session's own flag rather than
  -- inferring from result_bufnr, which only says whether the pane is built.
  local is_conflict = session and session.merge == true or false

  --- @type CodeDiffActionContext
  local ctx = {
    tabpage = tabpage,
    original_bufnr = original_bufnr,
    modified_bufnr = modified_bufnr,
    is_explorer_mode = is_explorer_mode or false,
    is_history_mode = is_history_mode or false,
    is_inline = is_inline or false,
    is_conflict = is_conflict,
  }

  -- Quit keymap (q)
  if keymaps.quit then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.quit, function()
      lifecycle.close(tabpage)
    end, { desc = "Close codediff tab" })
  end

  -- Hunk navigation (]c, [c)
  if keymaps.next_hunk then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.next_hunk, navigation.next_hunk, { desc = "Next hunk" })
  end
  if keymaps.prev_hunk then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.prev_hunk, navigation.prev_hunk, { desc = "Previous hunk" })
  end

  -- Explorer toggle (e) - only in explorer mode
  if is_explorer_mode and keymaps.toggle_explorer then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.toggle_explorer, function()
      panes.toggle_explorer(ctx)
    end, { desc = "Toggle explorer visibility" })
  end
  if is_explorer_mode and keymaps.focus_explorer then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.focus_explorer, function()
      panes.focus_explorer(ctx)
    end, { desc = "Focus explorer panel" })
  end

  -- Diff get/put (do, dp) - layout-aware semantics.
  -- Skipped in conflict mode: the merge view uses 2do/3do on the result pane
  -- instead. Not claiming the keys here means any mapping the user already had
  -- on do/dp is handed back for the duration of the merge, rather than deleted.
  if keymaps.diff_get and not is_conflict then
    local desc = is_inline and "Revert hunk to original" or "Get change from other buffer"
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.diff_get, function()
      diffget.diff_get(ctx)
    end, { desc = desc })
  end
  if keymaps.diff_put and not is_conflict then
    local desc = is_inline and "Accept change (no-op in inline)" or "Put change to other buffer"
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.diff_put, function()
      diffget.diff_put(ctx)
    end, { desc = desc })
  end
  if keymaps.open_in_prev_tab then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.open_in_prev_tab, function()
      panes.open_in_prev_tab(ctx)
    end, { desc = "Open buffer in previous tab" })
  end
  if keymaps.toggle_layout then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.toggle_layout, function()
      require("codediff.ui.view").toggle_layout(tabpage)
    end, { desc = "Toggle diff layout" })
  end
  if keymaps.toggle_compact then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.toggle_compact, function()
      compact.toggle(tabpage)
    end, { desc = "Toggle compact mode" })
  end

  -- Toggle stage/unstage (- key) - only in explorer mode
  -- Support legacy config: keymaps.explorer.toggle_stage (deprecated)
  if is_explorer_mode then
    local toggle_stage_key = keymaps.toggle_stage
    local explorer_keymaps = resolve.keymaps_for("explorer")

    -- Fallback to deprecated explorer.toggle_stage if view.toggle_stage not set
    if not toggle_stage_key and explorer_keymaps.toggle_stage then
      toggle_stage_key = explorer_keymaps.toggle_stage
      vim.schedule(function()
        vim.notify("[codediff] keymaps.explorer.toggle_stage is deprecated. Please use keymaps.view.toggle_stage instead.", vim.log.levels.WARN)
      end)
    end

    if toggle_stage_key then
      lifecycle.set_tab_keymap(tabpage, "n", toggle_stage_key, function()
        stage.toggle_stage(ctx)
      end, { desc = "Toggle stage/unstage" })
    end

    if keymaps.toggle_staged_view then
      lifecycle.set_tab_keymap(tabpage, "n", keymaps.toggle_staged_view, function()
        stage.toggle_staged_view(ctx)
      end, { desc = "Toggle staged/unstaged view for current file" })
    end
  end

  -- Help keymap (g?) - show floating window with available keymaps
  if keymaps.show_help then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.show_help, function()
      local ok, help = pcall(require, "codediff.ui.keymap_help")
      if ok and help then
        help.toggle(tabpage)
      else
        vim.notify_once("[codediff] failed to load codediff.ui.keymap_help: " .. tostring(help), vim.log.levels.WARN)
      end
    end, { desc = "Show keymap help" })
  end

  -- File navigation (]f, [f) - works in both explorer and history mode
  if is_explorer_mode or is_history_mode then
    if keymaps.next_file then
      lifecycle.set_tab_keymap(tabpage, "n", keymaps.next_file, navigation.next_file, { desc = "Next file" })
    end
    if keymaps.prev_file then
      lifecycle.set_tab_keymap(tabpage, "n", keymaps.prev_file, navigation.prev_file, { desc = "Previous file" })
    end
  end

  -- Hunk-level staging (S, U, D) - stage/unstage/discard individual hunks via git apply
  -- Only set on diff buffers, not explorer (S/U conflict with stage_all/unstage_all)
  local hunk_opts = { noremap = true, silent = true, nowait = true }
  local diff_bufs = {}
  if original_bufnr and vim.api.nvim_buf_is_valid(original_bufnr) then
    table.insert(diff_bufs, original_bufnr)
  end
  if modified_bufnr and vim.api.nvim_buf_is_valid(modified_bufnr) then
    table.insert(diff_bufs, modified_bufnr)
  end
  for _, bufnr in ipairs(diff_bufs) do
    if keymaps.stage_hunk then
      lifecycle.set_buf_keymap(tabpage, bufnr, "n", keymaps.stage_hunk, function()
        hunk.stage_hunk(ctx)
      end, vim.tbl_extend("force", hunk_opts, { desc = "Stage hunk under cursor" }))
    end
    if keymaps.unstage_hunk then
      lifecycle.set_buf_keymap(tabpage, bufnr, "n", keymaps.unstage_hunk, function()
        hunk.unstage_hunk(ctx)
      end, vim.tbl_extend("force", hunk_opts, { desc = "Unstage hunk under cursor" }))
    end
    if keymaps.discard_hunk then
      lifecycle.set_buf_keymap(tabpage, bufnr, "n", keymaps.discard_hunk, function()
        hunk.discard_hunk(ctx)
      end, vim.tbl_extend("force", hunk_opts, { desc = "Discard hunk under cursor" }))
    end

    -- Hunk textobject (ih) - select hunk lines in visual/operator-pending mode
    if keymaps.hunk_textobject then
      lifecycle.set_buf_keymap(tabpage, bufnr, { "o", "x" }, keymaps.hunk_textobject, function()
        hunk.select_hunk(ctx)
      end, vim.tbl_extend("force", hunk_opts, { desc = "Hunk textobject" }))
    end
  end

  if keymaps.align_move and not is_inline and config.options.diff.compute_moves then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.align_move, function()
      move.align_move(ctx)
    end, { desc = "Align moved code block" })
  end

  lifecycle.end_keymap_scope(tabpage, "view")

  -- Keep compact mode in sync when the diff view is (re)built — applies the
  -- configured default on open and re-folds on file switches (no-op if off).
  compact.refresh(tabpage)
end

return M
