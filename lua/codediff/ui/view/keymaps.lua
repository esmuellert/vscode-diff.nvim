-- Keymaps setup for diff view
local M = {}

local lifecycle = require("codediff.ui.lifecycle")
local auto_refresh = require("codediff.ui.auto_refresh")
local config = require("codediff.config")
local navigation = require("codediff.ui.view.navigation")
local render = require("codediff.ui.view.render")
local compact = require("codediff.ui.view.compact")

-- Centralized keymap setup for all diff view keymaps
-- This function sets up ALL keymaps in one place for better maintainability
function M.setup_all_keymaps(tabpage, original_bufnr, modified_bufnr, is_explorer_mode)
  local keymaps = config.options.keymaps.view

  -- Check mode context
  local session = lifecycle.get_session(tabpage)
  local is_history_mode = session and session.mode == "history"
  local is_inline = session and session.layout == "inline"

  -- Helper: Quit diff view
  local function quit_diff()
    -- Check for unsaved conflict files before closing
    if not lifecycle.confirm_close_with_unsaved(tabpage) then
      return -- User cancelled
    end
    if #vim.api.nvim_list_tabpages() == 1 then
      -- Last tab: clean up diff session first so session-persistence plugins
      -- don't save scratch/virtual buffers, then quit neovim entirely.
      lifecycle.cleanup_for_quit(tabpage)
      vim.cmd("qall")
    else
      vim.cmd("tabclose")
    end
  end

  -- Helper: Toggle explorer visibility (explorer mode only)
  local function toggle_explorer()
    local explorer_obj = lifecycle.get_explorer(tabpage)
    if not explorer_obj then
      vim.notify("No explorer found for this tab", vim.log.levels.WARN)
      return
    end
    local explorer = require("codediff.ui.explorer")
    explorer.toggle_visibility(explorer_obj)
  end

  -- Helper: Focus explorer panel (explorer mode only)
  local function focus_explorer()
    local explorer_obj = lifecycle.get_explorer(tabpage)
    if not explorer_obj then
      vim.notify("No explorer found for this tab", vim.log.levels.WARN)
      return
    end
    local split = explorer_obj.split
    if not split or not split.winid or not vim.api.nvim_win_is_valid(split.winid) then
      -- Explorer is hidden, show it first then focus
      local explorer = require("codediff.ui.explorer")
      explorer.toggle_visibility(explorer_obj)
    end
    if split and split.winid and vim.api.nvim_win_is_valid(split.winid) then
      vim.api.nvim_set_current_win(split.winid)
    end
  end

  -- Helper: Find hunk at cursor position
  -- Returns the hunk and its index, or nil if cursor is not in a hunk
  local function find_hunk_at_cursor()
    local session = lifecycle.get_session(tabpage)
    if not session or not session.stored_diff_result then
      return nil, nil
    end
    local diff_result = session.stored_diff_result
    if not diff_result.changes or #diff_result.changes == 0 then
      return nil, nil
    end

    local current_buf = vim.api.nvim_get_current_buf()
    -- In inline mode, always use modified ranges
    local is_original = not is_inline and current_buf == original_bufnr
    local cursor = vim.api.nvim_win_get_cursor(0)
    local current_line = cursor[1]

    for i, mapping in ipairs(diff_result.changes) do
      local start_line = is_original and mapping.original.start_line or mapping.modified.start_line
      local end_line = is_original and mapping.original.end_line or mapping.modified.end_line
      -- Check if cursor is within this hunk (end_line is exclusive)
      if current_line >= start_line and current_line < end_line then
        return mapping, i
      end
      -- Also match if it's a deletion (empty range) and cursor is at start
      if start_line == end_line and current_line == start_line then
        return mapping, i
      end
    end
    return nil, nil
  end

  -- Helper: Diff get - obtain change from other buffer to current buffer
  local function diff_get()
    local session = lifecycle.get_session(tabpage)
    if not session then
      return
    end

    if is_inline then
      -- Inline mode: revert modified lines to original
      if not vim.bo[modified_bufnr].modifiable then
        vim.notify("Buffer is not modifiable", vim.log.levels.WARN)
        return
      end

      local hunk, hunk_idx = find_hunk_at_cursor()
      if not hunk then
        vim.notify("No hunk at cursor position", vim.log.levels.WARN)
        return
      end

      local orig_lines = vim.api.nvim_buf_get_lines(original_bufnr, hunk.original.start_line - 1, hunk.original.end_line - 1, false)
      vim.api.nvim_buf_set_lines(modified_bufnr, hunk.modified.start_line - 1, hunk.modified.end_line - 1, false, orig_lines)
      auto_refresh.trigger(modified_bufnr)
      vim.api.nvim_echo({ { string.format("Reverted hunk %d", hunk_idx), "None" } }, false, {})
      return
    end

    -- Side-by-side mode: copy from other buffer to current
    local current_buf = vim.api.nvim_get_current_buf()
    local is_original = current_buf == original_bufnr
    local target_buf = current_buf
    local source_buf = is_original and modified_bufnr or original_bufnr

    -- Check if target buffer is modifiable
    if not vim.bo[target_buf].modifiable then
      vim.notify("Buffer is not modifiable", vim.log.levels.WARN)
      return
    end

    local hunk, hunk_idx = find_hunk_at_cursor()
    if not hunk then
      vim.notify("No hunk at cursor position", vim.log.levels.WARN)
      return
    end

    -- Get source and target ranges
    local source_range = is_original and hunk.modified or hunk.original
    local target_range = is_original and hunk.original or hunk.modified

    -- Get lines from source buffer
    local source_lines = vim.api.nvim_buf_get_lines(source_buf, source_range.start_line - 1, source_range.end_line - 1, false)

    -- Replace lines in target buffer
    vim.api.nvim_buf_set_lines(target_buf, target_range.start_line - 1, target_range.end_line - 1, false, source_lines)

    -- Trigger diff refresh to update highlights
    auto_refresh.trigger(target_buf)

    vim.api.nvim_echo({ { string.format("Obtained hunk %d", hunk_idx), "None" } }, false, {})
  end

  -- Helper: Diff put - put change from current buffer to other buffer
  local function diff_put()
    local session = lifecycle.get_session(tabpage)
    if not session then
      return
    end

    if is_inline then
      -- Inline mode: buffer already has modified content, dp is a no-op
      vim.notify("Buffer already contains the modified version. Use 'do' to revert to original.", vim.log.levels.INFO)
      return
    end

    -- Side-by-side mode: copy from current buffer to other
    local current_buf = vim.api.nvim_get_current_buf()
    local is_original = current_buf == original_bufnr
    local source_buf = current_buf
    local target_buf = is_original and modified_bufnr or original_bufnr

    -- Check if target buffer is modifiable
    if not vim.bo[target_buf].modifiable then
      vim.notify("Target buffer is not modifiable", vim.log.levels.WARN)
      return
    end

    local hunk, hunk_idx = find_hunk_at_cursor()
    if not hunk then
      vim.notify("No hunk at cursor position", vim.log.levels.WARN)
      return
    end

    -- Get source and target ranges
    local source_range = is_original and hunk.original or hunk.modified
    local target_range = is_original and hunk.modified or hunk.original

    -- Get lines from source buffer
    local source_lines = vim.api.nvim_buf_get_lines(source_buf, source_range.start_line - 1, source_range.end_line - 1, false)

    -- Replace lines in target buffer
    vim.api.nvim_buf_set_lines(target_buf, target_range.start_line - 1, target_range.end_line - 1, false, source_lines)

    -- Trigger diff refresh to update highlights
    auto_refresh.trigger(target_buf)

    vim.api.nvim_echo({ { string.format("Put hunk %d", hunk_idx), "None" } }, false, {})
  end

  -- Helper: Toggle stage/unstage for current file (tab-wide)
  -- Works in: explorer buffer, diff buffers (original/modified)
  -- Does nothing in: history buffer, other buffers
  local function toggle_stage()
    local current_buf = vim.api.nvim_get_current_buf()
    local explorer = lifecycle.get_explorer(tabpage)
    local session = lifecycle.get_session(tabpage)

    if not session then
      return
    end

    -- Only available in explorer mode with git
    if not is_explorer_mode then
      vim.notify("Stage/unstage only available in explorer mode", vim.log.levels.WARN)
      return
    end

    if not explorer or not explorer.git_root then
      vim.notify("Stage/unstage only available in git mode", vim.log.levels.WARN)
      return
    end

    -- Case 1: Cursor in explorer buffer
    if explorer.bufnr and current_buf == explorer.bufnr then
      -- Delegate to explorer action (handles files and directories)
      local explorer_module = require("codediff.ui.explorer")
      explorer_module.toggle_stage_entry(explorer, explorer.tree)
      return
    end

    -- Case 2: Cursor in diff buffers (original or modified)
    if current_buf == original_bufnr or current_buf == modified_bufnr then
      local file_path = explorer.current_file_path
      local group = explorer.current_file_group

      -- Guard: must have a current file selected
      if not file_path then
        vim.notify("No file selected", vim.log.levels.WARN)
        return
      end

      -- Guard: file must be stageable
      if not group or (group ~= "staged" and group ~= "unstaged" and group ~= "conflicts") then
        vim.notify("Current file cannot be staged/unstaged", vim.log.levels.WARN)
        return
      end

      local explorer_module = require("codediff.ui.explorer")
      explorer_module.toggle_stage_file(explorer.git_root, file_path, group)
      return
    end

    -- Case 3: Other buffers (history, etc.) - do nothing silently
  end

  -- Helper: Open the current real buffer in the previous tab (or create one before)
  local function open_in_prev_tab()
    local session = lifecycle.get_session(tabpage)
    if not session then
      return
    end

    local current_buf = vim.api.nvim_get_current_buf()
    local side = nil
    if current_buf == original_bufnr then
      side = "original"
    elseif current_buf == modified_bufnr then
      side = "modified"
    end

    -- Only operate on diff buffers; ignore explorer/history/result silently
    if not side then
      return
    end

    local is_virtual = (side == "original" and lifecycle.is_original_virtual(tabpage)) or (side == "modified" and lifecycle.is_modified_virtual(tabpage))

    -- For virtual buffers, resolve the real file on disk
    local target_file
    if is_virtual then
      local original_path, modified_path = lifecycle.get_paths(tabpage)
      local rel_path = side == "original" and original_path or modified_path
      if not rel_path or rel_path == "" then
        vim.notify("Buffer has no associated file path", vim.log.levels.WARN)
        return
      end
      local git_root = session.git_root
      target_file = git_root .. "/" .. rel_path
    else
      target_file = vim.api.nvim_buf_get_name(current_buf)
      if target_file == "" then
        vim.notify("Buffer has no name; cannot open in previous tab", vim.log.levels.WARN)
        return
      end
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local current_tab = vim.api.nvim_get_current_tabpage()
    local tabs = vim.api.nvim_list_tabpages()

    local current_index = nil
    for i, tab in ipairs(tabs) do
      if tab == current_tab then
        current_index = i
        break
      end
    end

    local target_tab
    if current_index and current_index > 1 then
      target_tab = tabs[current_index - 1]
    else
      vim.cmd("tabnew")
      target_tab = vim.api.nvim_get_current_tabpage()
      vim.cmd("tabmove 0")
    end

    if vim.api.nvim_get_current_tabpage() ~= target_tab then
      vim.api.nvim_set_current_tabpage(target_tab)
    end

    local target_win = vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(target_win) then
      vim.notify("No valid window in target tab to open buffer", vim.log.levels.ERROR)
      return
    end

    local ok, err
    if is_virtual then
      ok, err = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(target_file))
    else
      ok, err = pcall(vim.api.nvim_win_set_buf, target_win, current_buf)
    end
    if not ok then
      vim.notify("Failed to open buffer in previous tab: " .. err, vim.log.levels.ERROR)
      return
    end

    pcall(vim.api.nvim_win_set_cursor, target_win, cursor)

    -- Optionally close codediff after navigating to file
    if config.options.keymaps.view.close_on_open_in_prev_tab then
      -- Switch back to diff tab and close it
      if vim.api.nvim_tabpage_is_valid(current_tab) then
        vim.api.nvim_set_current_tabpage(current_tab)
        vim.cmd("tabclose")
      end
    end
  end

  -- ========================================================================
  -- Hunk-level staging (S, U)
  -- Generates a unified diff patch for the hunk under cursor and applies it
  -- to the git index via `git apply --cached --unidiff-zero`.
  -- Stage (S): applies the hunk's changes to the index (working → staged)
  -- Unstage (U): reverse-applies to remove the hunk from the index
  -- ========================================================================

  --- Build a minimal unified diff patch string for a single hunk.
  --- The patch has no context lines (used with --unidiff-zero).
  --- @param file_path string relative path from git root
  --- @param orig_lines string[] lines from the original (HEAD) buffer for this hunk
  --- @param mod_lines string[] lines from the modified (working/staged) buffer for this hunk
  --- @param orig_start number 1-based start line in original file
  --- @param mod_start number 1-based start line in modified file
  --- @return string patch valid unified diff patch
  local function build_hunk_patch(file_path, orig_lines, mod_lines, orig_start, mod_start)
    local orig_count = #orig_lines
    local mod_count = #mod_lines

    -- For pure insertions with 0 original lines, git expects start to be
    -- the line AFTER which content is inserted (0 if at very start)
    local hdr_orig_start = orig_count == 0 and (orig_start > 0 and orig_start - 1 or 0) or orig_start
    local hdr_mod_start = mod_count == 0 and (mod_start > 0 and mod_start - 1 or 0) or mod_start

    local parts = {
      string.format("--- a/%s", file_path),
      string.format("+++ b/%s", file_path),
      string.format("@@ -%d,%d +%d,%d @@", hdr_orig_start, orig_count, hdr_mod_start, mod_count),
    }

    for _, line in ipairs(orig_lines) do
      table.insert(parts, "-" .. line)
    end
    for _, line in ipairs(mod_lines) do
      table.insert(parts, "+" .. line)
    end

    -- Patch must end with a newline
    return table.concat(parts, "\n") .. "\n"
  end

  -- Helper: Stage hunk under cursor to git index
  local function stage_hunk()
    local session = lifecycle.get_session(tabpage)
    if not session or not session.git_root then
      vim.notify("Not in a git repository", vim.log.levels.WARN)
      return
    end

    -- Only allow staging from unstaged views (working tree changes)
    if session.modified_revision ~= nil then
      vim.notify("Stage only works on unstaged changes", vim.log.levels.WARN)
      return
    end

    local hunk, hunk_idx = find_hunk_at_cursor()
    if not hunk then
      vim.notify("No hunk at cursor position", vim.log.levels.WARN)
      return
    end

    -- Get the file path relative to git root
    local file_path = session.original_path or session.modified_path
    if not file_path or file_path == "" then
      vim.notify("No file path for staging", vim.log.levels.WARN)
      return
    end

    local stage_orig_buf, stage_mod_buf = lifecycle.get_buffers(tabpage)
    if not stage_orig_buf or not stage_mod_buf or not vim.api.nvim_buf_is_valid(stage_orig_buf) or not vim.api.nvim_buf_is_valid(stage_mod_buf) then
      vim.notify("Diff buffers are no longer available", vim.log.levels.WARN)
      return
    end

    -- Read lines from both buffers for this hunk
    local orig_lines = vim.api.nvim_buf_get_lines(stage_orig_buf, hunk.original.start_line - 1, hunk.original.end_line - 1, false)
    local mod_lines = vim.api.nvim_buf_get_lines(stage_mod_buf, hunk.modified.start_line - 1, hunk.modified.end_line - 1, false)

    local patch = build_hunk_patch(file_path, orig_lines, mod_lines, hunk.original.start_line, hunk.modified.start_line)

    local git = require("codediff.core.git")
    git.apply_patch(session.git_root, patch, false, function(err)
      if err then
        vim.notify("Failed to stage hunk: " .. err, vim.log.levels.ERROR)
        return
      end
      vim.notify(string.format("Staged hunk %d", hunk_idx), vim.log.levels.INFO)
    end)
  end

  -- Helper: Unstage hunk under cursor from git index
  local function unstage_hunk()
    local session = lifecycle.get_session(tabpage)
    if not session or not session.git_root then
      vim.notify("Not in a git repository", vim.log.levels.WARN)
      return
    end

    -- Only allow unstaging from staged views
    if session.modified_revision ~= ":0" then
      vim.notify("Unstage only works on staged changes", vim.log.levels.WARN)
      return
    end

    local hunk, hunk_idx = find_hunk_at_cursor()
    if not hunk then
      vim.notify("No hunk at cursor position", vim.log.levels.WARN)
      return
    end

    local file_path = session.original_path or session.modified_path
    if not file_path or file_path == "" then
      vim.notify("No file path for unstaging", vim.log.levels.WARN)
      return
    end

    local unstage_orig_buf, unstage_mod_buf = lifecycle.get_buffers(tabpage)
    if not unstage_orig_buf or not unstage_mod_buf or not vim.api.nvim_buf_is_valid(unstage_orig_buf) or not vim.api.nvim_buf_is_valid(unstage_mod_buf) then
      vim.notify("Diff buffers are no longer available", vim.log.levels.WARN)
      return
    end

    -- Read lines from both buffers for this hunk
    local orig_lines = vim.api.nvim_buf_get_lines(unstage_orig_buf, hunk.original.start_line - 1, hunk.original.end_line - 1, false)
    local mod_lines = vim.api.nvim_buf_get_lines(unstage_mod_buf, hunk.modified.start_line - 1, hunk.modified.end_line - 1, false)

    local patch = build_hunk_patch(file_path, orig_lines, mod_lines, hunk.original.start_line, hunk.modified.start_line)

    local git = require("codediff.core.git")
    git.apply_patch(session.git_root, patch, true, function(err)
      if err then
        vim.notify("Failed to unstage hunk: " .. err, vim.log.levels.ERROR)
        return
      end
      vim.notify(string.format("Unstaged hunk %d", hunk_idx), vim.log.levels.INFO)
    end)
  end

  -- Helper: Discard hunk under cursor from working tree
  local function discard_hunk()
    local session = lifecycle.get_session(tabpage)
    if not session or not session.git_root then
      vim.notify("Not in a git repository", vim.log.levels.WARN)
      return
    end

    -- Only allow discarding in unstaged views (working tree changes)
    if session.modified_revision ~= nil then
      vim.notify("Discard only works on unstaged changes (working tree)", vim.log.levels.WARN)
      return
    end

    local hunk, hunk_idx = find_hunk_at_cursor()
    if not hunk then
      vim.notify("No hunk at cursor position", vim.log.levels.WARN)
      return
    end

    local file_path = session.original_path or session.modified_path
    if not file_path or file_path == "" then
      vim.notify("No file path for discarding", vim.log.levels.WARN)
      return
    end

    -- Prompt for confirmation before discarding (destructive operation)
    local prompt = string.format("Discard hunk %d?", hunk_idx)
    local choice = vim.fn.confirm(prompt, "&Discard\n&Cancel", 2, "Warning")
    if choice ~= 1 then
      return
    end

    local discard_orig_buf, discard_mod_buf = lifecycle.get_buffers(tabpage)
    if not discard_orig_buf or not discard_mod_buf or not vim.api.nvim_buf_is_valid(discard_orig_buf) or not vim.api.nvim_buf_is_valid(discard_mod_buf) then
      vim.notify("Diff buffers are no longer available", vim.log.levels.WARN)
      return
    end

    -- Read lines from both buffers for this hunk
    local orig_lines = vim.api.nvim_buf_get_lines(discard_orig_buf, hunk.original.start_line - 1, hunk.original.end_line - 1, false)
    local mod_lines = vim.api.nvim_buf_get_lines(discard_mod_buf, hunk.modified.start_line - 1, hunk.modified.end_line - 1, false)

    local patch = build_hunk_patch(file_path, orig_lines, mod_lines, hunk.original.start_line, hunk.modified.start_line)

    local git = require("codediff.core.git")
    git.discard_hunk_patch(session.git_root, patch, function(err)
      if err then
        vim.notify("Failed to discard hunk: " .. err, vim.log.levels.ERROR)
        return
      end
      vim.notify(string.format("Discarded hunk %d", hunk_idx), vim.log.levels.INFO)
    end)
  end

  -- ========================================================================
  -- Bind all keymaps using unified API (one place for all keymaps!)
  -- ========================================================================

  -- Quit keymap (q)
  if keymaps.quit then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.quit, quit_diff, { desc = "Close codediff tab" })
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
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.toggle_explorer, toggle_explorer, { desc = "Toggle explorer visibility" })
  end
  if is_explorer_mode and keymaps.focus_explorer then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.focus_explorer, focus_explorer, { desc = "Focus explorer panel" })
  end

  -- Diff get/put (do, dp) - layout-aware semantics
  if keymaps.diff_get then
    local desc = is_inline and "Revert hunk to original" or "Get change from other buffer"
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.diff_get, diff_get, { desc = desc })
  end
  if keymaps.diff_put then
    local desc = is_inline and "Accept change (no-op in inline)" or "Put change to other buffer"
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.diff_put, diff_put, { desc = desc })
  end
  if keymaps.open_in_prev_tab then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.open_in_prev_tab, open_in_prev_tab, { desc = "Open buffer in previous tab" })
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
    local explorer_keymaps = config.options.keymaps.explorer or {}

    -- Fallback to deprecated explorer.toggle_stage if view.toggle_stage not set
    if not toggle_stage_key and explorer_keymaps.toggle_stage then
      toggle_stage_key = explorer_keymaps.toggle_stage
      vim.schedule(function()
        vim.notify("[codediff] keymaps.explorer.toggle_stage is deprecated. Please use keymaps.view.toggle_stage instead.", vim.log.levels.WARN)
      end)
    end

    if toggle_stage_key then
      lifecycle.set_tab_keymap(tabpage, "n", toggle_stage_key, toggle_stage, { desc = "Toggle stage/unstage" })
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
      vim.keymap.set("n", keymaps.stage_hunk, stage_hunk, vim.tbl_extend("force", hunk_opts, { buffer = bufnr, desc = "Stage hunk under cursor" }))
    end
    if keymaps.unstage_hunk then
      vim.keymap.set("n", keymaps.unstage_hunk, unstage_hunk, vim.tbl_extend("force", hunk_opts, { buffer = bufnr, desc = "Unstage hunk under cursor" }))
    end
    if keymaps.discard_hunk then
      vim.keymap.set("n", keymaps.discard_hunk, discard_hunk, vim.tbl_extend("force", hunk_opts, { buffer = bufnr, desc = "Discard hunk under cursor" }))
    end

    -- Hunk textobject (ih) - select hunk lines in visual/operator-pending mode
    if keymaps.hunk_textobject then
      local function select_hunk()
        local mapping = find_hunk_at_cursor()
        if not mapping then
          return
        end

        local current_buf = vim.api.nvim_get_current_buf()
        local is_original = current_buf == original_bufnr
        local start_line = is_original and mapping.original.start_line or mapping.modified.start_line
        local end_line = is_original and mapping.original.end_line or mapping.modified.end_line

        -- end_line is exclusive, and empty ranges (deletions) can't be selected
        if start_line >= end_line then
          return
        end

        vim.cmd("normal! " .. start_line .. "GV" .. (end_line - 1) .. "G")
      end

      vim.keymap.set({ "o", "x" }, keymaps.hunk_textobject, select_hunk, vim.tbl_extend("force", hunk_opts, { buffer = bufnr, desc = "Hunk textobject" }))
    end
  end

  -- ========================================================================
  -- Align moved code (gm)
  -- Temporarily align other pane to show paired move block
  -- ========================================================================

  local function align_move()
    local session = lifecycle.get_session(tabpage)
    if not session or not session.stored_diff_result or not session.stored_diff_result.moves then
      return
    end
    if is_inline then
      return
    end -- Only works in side-by-side

    local moves = session.stored_diff_result.moves
    if #moves == 0 then
      vim.notify("No moved code blocks in current diff", vim.log.levels.INFO)
      return
    end

    local current_buf = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

    -- Read current buffers from session (not closure — may have changed via file switch)
    local sess_orig_buf = session.original_bufnr
    local sess_mod_buf = session.modified_bufnr

    -- Find which move the cursor is in
    local current_move = nil
    local is_on_original = current_buf == sess_orig_buf
    for _, move in ipairs(moves) do
      local range = is_on_original and move.original or move.modified
      if cursor_line >= range.start_line and cursor_line < range.end_line then
        current_move = move
        break
      end
    end

    if not current_move then
      vim.notify("Not on a moved code block", vim.log.levels.INFO)
      return
    end

    local current_win = vim.api.nvim_get_current_win()
    local other_win = is_on_original and session.modified_win or session.original_win
    if not vim.api.nvim_win_is_valid(other_win) then
      return
    end

    local my_range = is_on_original and current_move.original or current_move.modified
    local other_range = is_on_original and current_move.modified or current_move.original

    -- Save full view state of both windows
    local current_view = vim.api.nvim_win_call(current_win, function()
      return vim.fn.winsaveview()
    end)
    local other_view = vim.api.nvim_win_call(other_win, function()
      return vim.fn.winsaveview()
    end)
    local saved_scrollbind_current = vim.wo[current_win].scrollbind
    local saved_scrollbind_other = vim.wo[other_win].scrollbind

    -- Disable scrollbind
    vim.wo[current_win].scrollbind = false
    vim.wo[other_win].scrollbind = false

    -- Align using the annotation virt_line as anchor:
    -- Both sides have "⇄ moved" above their first moved line.
    -- Use winline() to get the actual visual row (accounts for virtual/filler lines).
    local my_first = my_range.start_line
    local other_first = other_range.start_line

    -- Get actual visual row of the moved block start (accounts for filler virt_lines)
    -- Save and restore cursor so the user's position is not disturbed.
    local my_visual_row = vim.api.nvim_win_call(current_win, function()
      local saved_pos = vim.api.nvim_win_get_cursor(current_win)
      vim.api.nvim_win_set_cursor(current_win, { my_first, 0 })
      local row = vim.fn.winline()
      vim.api.nvim_win_set_cursor(current_win, saved_pos)
      return row
    end)

    -- Set other pane: position other_first at the same visual row
    -- winline() is 1-based from top of window
    vim.api.nvim_win_call(other_win, function()
      -- First scroll to the target line at top of window
      vim.api.nvim_win_set_cursor(other_win, { other_first, 0 })
      vim.cmd("normal! zt")
      -- Now scroll down to match the visual offset (Ctrl-Y scrolls view up, line moves down)
      if my_visual_row > 1 then
        local keys = vim.api.nvim_replace_termcodes((my_visual_row - 1) .. "<C-y>", true, false, true)
        vim.api.nvim_feedkeys(keys, "nx", false)
      end
    end)

    -- Restore function — called when cursor leaves moved block or switches window
    local augroup = vim.api.nvim_create_augroup("codediff_move_align_" .. tabpage, { clear = true })
    local restored = false

    local function restore()
      if restored then
        return
      end
      restored = true
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
      if not vim.api.nvim_win_is_valid(current_win) or not vim.api.nvim_win_is_valid(other_win) then
        return
      end
      -- Restore views first (before scrollbind)
      vim.api.nvim_win_call(other_win, function()
        vim.fn.winrestview(other_view)
      end)
      vim.api.nvim_win_call(current_win, function()
        vim.fn.winrestview(current_view)
      end)
      -- Use the same anchor technique as initial render to establish scrollbind
      local sess = lifecycle.get_session(tabpage)
      local orig_win = sess and sess.original_win or current_win
      local mod_win = sess and sess.modified_win or other_win
      local orig_buf_nr = sess and sess.original_bufnr or vim.api.nvim_win_get_buf(orig_win)
      local mod_buf_nr = sess and sess.modified_bufnr or vim.api.nvim_win_get_buf(mod_win)
      local diff_result = sess and sess.stored_diff_result
      local orig_cur = { current_view.lnum, current_view.col }
      local mod_cur = { other_view.lnum, other_view.col }
      if not is_on_original then
        orig_cur, mod_cur = mod_cur, orig_cur
      end
      render.establish_scrollbind(orig_win, mod_win, orig_buf_nr, mod_buf_nr, diff_result, orig_cur, mod_cur)
    end

    -- Restore when cursor moves out of the moved block
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = augroup,
      buffer = current_buf,
      callback = function()
        local new_line = vim.api.nvim_win_get_cursor(0)[1]
        if new_line < my_range.start_line or new_line >= my_range.end_line then
          restore()
        end
      end,
    })

    -- Restore when user switches to another window (WinLeave)
    -- Use vim.schedule to defer restore until after Neovim finishes
    -- the window switch and cursor placement from the click event.
    vim.api.nvim_create_autocmd("WinLeave", {
      group = augroup,
      callback = function()
        vim.schedule(restore)
      end,
    })
  end

  if keymaps.align_move and not is_inline and config.options.diff.compute_moves then
    lifecycle.set_tab_keymap(tabpage, "n", keymaps.align_move, align_move, { desc = "Align moved code block" })
  end

  -- Re-apply compact mode folds if active (persists across file switches)
  compact.reapply(tabpage)
end

return M
