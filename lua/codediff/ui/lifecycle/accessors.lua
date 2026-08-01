-- Accessor functions (getters and setters) for diff sessions
local M = {}
-- Eagerly loaded: accessors run from scheduled callbacks that may execute
-- after the CWD changed, where a first-time require would fail.
local keymap = require("codediff.keymap")

-- Lazy require to avoid circular dependency: init → session → accessors → session
local function get_active_diffs()
  return require("codediff.ui.lifecycle.session").get_active_diffs()
end

-- Check if a revision represents a virtual buffer
local function is_virtual_revision(revision)
  return revision ~= nil and revision ~= "WORKING"
end

-- ============================================================================
-- PUBLIC API - GETTERS (return copies/values, safe)
-- ============================================================================

--- Get session
--- @param tabpage number
--- @return table|nil
function M.get_session(tabpage)
  local active_diffs = get_active_diffs()
  return active_diffs[tabpage]
end

--- Get mode
function M.get_mode(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  return sess and sess.mode or nil
end

--- Get current session layout
function M.get_layout(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  return sess and sess.layout or nil
end

--- Get git context
function M.get_git_context(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return nil
  end

  return {
    git_root = sess.git_root,
    original_revision = sess.original_revision,
    modified_revision = sess.modified_revision,
  }
end

--- Get buffer IDs
function M.get_buffers(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return nil, nil
  end
  return sess.original_bufnr, sess.modified_bufnr
end

--- Get window IDs
function M.get_windows(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return nil, nil
  end
  return sess.original_win, sess.modified_win
end

--- Get path refs
---@return Path? original, Path? modified
function M.get_paths(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return nil, nil
  end
  return sess.original, sess.modified
end

--- Find tabpage containing a buffer
function M.find_tabpage_by_buffer(bufnr)
  local active_diffs = get_active_diffs()
  for tabpage, sess in pairs(active_diffs) do
    if sess.original_bufnr == bufnr or sess.modified_bufnr == bufnr or sess.result_bufnr == bufnr then
      return tabpage
    end
  end
  return nil
end

--- Check if original buffer is virtual
function M.is_original_virtual(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end
  return is_virtual_revision(sess.original_revision)
end

--- Check if modified buffer is virtual
function M.is_modified_virtual(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end
  return is_virtual_revision(sess.modified_revision)
end

--- Check if suspended
function M.is_suspended(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  return sess and sess.suspended or false
end

--- Get explorer reference (for explorer mode)
function M.get_explorer(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  return sess and sess.explorer
end

--- Get the merge base (stage :1) content for the conflict file.
--- This is the common ancestor — the real "original" — used by smart-combine
--- and discard operations that need merge-base coordinates. Distinct from
--- result_base_lines, which is the auto-merged *seed* content of the Result
--- buffer (and not the merge base).
function M.get_merge_base_lines(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  return sess and sess.merge_base_lines
end

--- Get the seed content of the Result buffer (auto-merged result).
--- This is what the Result buffer was initialized to, and what every
--- accept/discard action compares against to decide whether a conflict
--- region is still in its initial unresolved state. NOT the merge base —
--- see get_merge_base_lines for that.
function M.get_result_base_lines(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  return sess and sess.result_base_lines
end

--- Get result buffer and window
function M.get_result(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return nil, nil
  end
  return sess.result_bufnr, sess.result_win
end

--- Get conflict blocks for a session
--- @param tabpage number
--- @return table|nil List of conflict blocks
function M.get_conflict_blocks(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  return sess and sess.conflict_blocks
end

--- Get all conflict files for a session
function M.get_conflict_files(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return {}
  end
  return sess.conflict_files or {}
end

--- Check if any conflict files have unsaved changes
--- Returns list of unsaved file paths
function M.get_unsaved_conflict_files(tabpage)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess or not sess.conflict_files then
    return {}
  end

  local unsaved = {}
  for file_path, _ in pairs(sess.conflict_files) do
    -- Find buffer for this file
    local bufnr = vim.fn.bufnr(file_path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      if vim.bo[bufnr].modified then
        table.insert(unsaved, file_path)
      end
    end
  end
  return unsaved
end

-- ============================================================================
-- PUBLIC API - SETTERS (validated mutations)
-- ============================================================================

--- Update suspended state
function M.update_suspended(tabpage, suspended)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  sess.suspended = suspended
  return true
end

--- Update session layout
function M.update_layout(tabpage, layout)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  sess.layout = layout
  return true
end

--- Update diff result (cached)
function M.update_diff_result(tabpage, diff_lines)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  sess.stored_diff_result = diff_lines
  return true
end

--- Update changedtick
function M.update_changedtick(tabpage, original_tick, modified_tick)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  sess.changedtick.original = original_tick
  sess.changedtick.modified = modified_tick
  return true
end

--- Update mtime
function M.update_mtime(tabpage, original_mtime, modified_mtime)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  sess.mtime.original = original_mtime
  sess.mtime.modified = modified_mtime
  return true
end

--- Update path refs (for file switching/sync)
---@param original Path
---@param modified Path
function M.update_paths(tabpage, original, modified)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  sess.original = original
  sess.modified = modified
  return true
end

--- Update buffer numbers (for file switching/sync when buffers change)
--- Also updates buffer states (for suspend/resume to work correctly)
function M.update_buffers(tabpage, original_bufnr, modified_bufnr)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  local state = require("codediff.ui.lifecycle.state")

  -- Hand mappings back to any buffer that is leaving the session. Without this
  -- the previous file keeps codediff's keys until the tab is closed.
  if sess.keymaps then
    local keep = {}
    if original_bufnr then
      keep[original_bufnr] = true
    end
    if modified_bufnr then
      keep[modified_bufnr] = true
    end
    if sess.explorer and sess.explorer.bufnr then
      keep[sess.explorer.bufnr] = true
    end
    if sess.result_bufnr then
      keep[sess.result_bufnr] = true
    end
    sess.keymaps:detach_buffers_except(keep)
  end

  sess.original_bufnr = original_bufnr
  sess.modified_bufnr = modified_bufnr

  -- Save buffer states for new buffers (critical for suspend/resume!)
  sess.original_state = state.save_buffer_state(original_bufnr)
  sess.modified_state = state.save_buffer_state(modified_bufnr)

  return true
end

--- Update git root (for file switching when changing repos)
function M.update_git_root(tabpage, git_root)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  sess.git_root = git_root
  return true
end

--- Update revisions (for file switching/sync)
function M.update_revisions(tabpage, original_revision, modified_revision)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  sess.original_revision = original_revision
  sess.modified_revision = modified_revision
  return true
end

--- Set explorer reference (for explorer mode)
function M.set_explorer(tabpage, explorer)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  sess.explorer = explorer
  if sess.reapply_keymaps then
    sess.reapply_keymaps()
  end
  return true
end

--- Set result buffer and window (for conflict mode)
function M.set_result(tabpage, result_bufnr, result_win)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  -- Leaving conflict mode: retire the conflict mappings so do/dp and the
  -- ordinary view mappings can be claimed again on the next setup pass.
  if result_bufnr == nil and sess.result_bufnr ~= nil and sess.keymaps then
    sess.keymaps:release_scope("conflict")
  end

  sess.result_bufnr = result_bufnr
  sess.result_win = result_win

  -- Mark result window with restore flag
  if result_win and vim.api.nvim_win_is_valid(result_win) then
    vim.w[result_win].codediff_restore = 1
  end

  return true
end

--- Store the seed content for the Result buffer (auto-merged result).
--- See get_result_base_lines for semantics.
function M.set_result_base_lines(tabpage, result_base_lines)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end
  sess.result_base_lines = result_base_lines
  return true
end

--- Store the merge base (stage :1) content for the conflict file.
--- See get_merge_base_lines for semantics; this is kept separate from
--- result_base_lines so smart-combine can still walk merge-base coordinates
--- after the Result buffer has been auto-merged.
function M.set_merge_base_lines(tabpage, merge_base_lines)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end
  sess.merge_base_lines = merge_base_lines
  return true
end

--- Store conflict blocks (mapping alignments) for a session
--- @param tabpage number
--- @param blocks table List of conflict blocks from compute_mapping_alignments
function M.set_conflict_blocks(tabpage, blocks)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end
  sess.conflict_blocks = blocks
  return true
end

--- Track a file opened in conflict mode (for unsaved warning)
function M.track_conflict_file(tabpage, file_path)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  sess.conflict_files = sess.conflict_files or {}
  sess.conflict_files[file_path] = true
  return true
end

--- Prompt user about unsaved conflict files before closing
--- Returns true if user confirms close, false if cancelled
function M.confirm_close_with_unsaved(tabpage)
  local unsaved = M.get_unsaved_conflict_files(tabpage)
  if #unsaved == 0 then
    return true -- No unsaved files, proceed
  end

  -- Build message
  local msg = "The following merge result files have unsaved changes:\n\n"
  for _, path in ipairs(unsaved) do
    -- Show just filename for readability
    local filename = vim.fn.fnamemodify(path, ":t")
    msg = msg .. "  • " .. filename .. "\n"
  end
  msg = msg .. "\nDiscard changes and close?"

  -- Show confirmation dialog
  local choice = vim.fn.confirm(msg, "&Discard\n&Cancel", 2, "Warning")

  if choice == 1 then
    -- Discard: reload buffers from disk to restore original content (with conflict markers)
    for _, path in ipairs(unsaved) do
      local bufnr = vim.fn.bufnr(path)
      if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
        -- Reload from disk to restore original file content
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("edit!")
        end)
      end
    end
    return true
  else
    -- Cancel
    return false
  end
end

--- Registry that owns every mapping this session installs.
--- Created lazily so sessions built by older call paths still work.
--- @param sess table
--- @return table|nil registry
local function registry_for(sess)
  if not sess then
    return nil
  end
  if not sess.keymaps then
    sess.keymaps = keymap.new("codediff-session")
  end
  return sess.keymaps
end

--- Buffers that currently belong to a session, by role.
--- @param sess table
--- @return table<string, number> roles
local function session_buffers(sess)
  local buffers = {}
  if sess.original_bufnr and vim.api.nvim_buf_is_valid(sess.original_bufnr) then
    buffers.original = sess.original_bufnr
  end
  if sess.modified_bufnr and vim.api.nvim_buf_is_valid(sess.modified_bufnr) then
    buffers.modified = sess.modified_bufnr
  end
  local explorer = sess.explorer
  if explorer and explorer.bufnr and vim.api.nvim_buf_is_valid(explorer.bufnr) then
    buffers.panel = explorer.bufnr
  end
  if sess.result_bufnr and vim.api.nvim_buf_is_valid(sess.result_bufnr) then
    buffers.result = sess.result_bufnr
  end
  return buffers
end

--- Set a keymap on all buffers in the diff tab (both diff buffers + explorer + result)
--- This is the unified API for setting tab-wide keymaps
--- @param tabpage number Tab page ID
--- @param mode string|string[] Keymap mode ('n', 'v', etc.)
--- @param lhs string Left-hand side of the keymap
--- @param rhs function|string Right-hand side (callback or command)
--- @param opts? table Optional keymap options (will be merged with buffer-local defaults)
--- @return boolean success True if keymaps were set
function M.set_tab_keymap(tabpage, mode, lhs, rhs, opts)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  local reg = registry_for(sess)
  local base_opts = { noremap = true, silent = true, nowait = true }
  local merged = vim.tbl_extend("force", base_opts, opts or {})

  for _, bufnr in pairs(session_buffers(sess)) do
    reg:claim(bufnr, mode, lhs, rhs, merged)
  end

  return true
end

--- Set a keymap on one specific buffer, owned by the session's registry.
--- Used for mappings that are scoped to a single role (hunk operations and the
--- hunk textobject on diff panes, conflict actions, panel actions).
--- @param tabpage number
--- @param bufnr number
--- @param mode string|string[]
--- @param lhs string|false|nil Configured binding; false/nil silently disables
--- @param rhs function|string
--- @param opts? table Forwarded verbatim to vim.keymap.set
--- @param meta? table { suspendable = boolean, priority = integer }
--- @return boolean success
function M.set_buf_keymap(tabpage, bufnr, mode, lhs, rhs, opts, meta)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    -- No session to own the mapping (a panel built outside a diff tab, for
    -- example). Fall back to a plain buffer-local mapping so behavior matches
    -- the pre-registry implementation rather than silently binding nothing.
    local resolved = keymap.resolve(lhs)
    if not resolved or not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
      return false
    end
    return pcall(vim.keymap.set, mode, resolved, rhs, vim.tbl_extend("force", opts or {}, { buffer = bufnr }))
  end
  return registry_for(sess):claim(bufnr, mode, lhs, rhs, opts, meta)
end

--- True when the session currently owns a mapping for `lhs`.
--- Used by the help popup so it can describe what is really bound rather than
--- a hand-maintained list that drifts.
--- @param tabpage number
--- @param lhs string|false|nil
--- @param mode string|nil Restrict to one mode; any mode when omitted
--- @param bufnr number|nil Restrict to one buffer; any session buffer when omitted
--- @return boolean
function M.owns_keymap(tabpage, lhs, mode, bufnr)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return false
  end
  return sess.keymaps:owns(lhs, mode, bufnr)
end

--- Keys the session owns that are expected to appear in the help popup.
--- @param tabpage number
--- @return table<string, boolean> canonical lhs -> true
function M.documented_keymaps(tabpage)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return {}
  end
  return sess.keymaps:documented_keys()
end

--- Begin a keymap setup pass for `scope` on this session.
--- Claims made until end_keymap_scope are tagged; anything in the scope the
--- pass does not re-claim is released, so a shape change (layout toggle,
--- leaving conflict mode, reconfiguration) cannot leave stale mappings behind.
--- @param tabpage number
--- @param scope string
function M.begin_keymap_scope(tabpage, scope)
  local sess = get_active_diffs()[tabpage]
  if sess then
    registry_for(sess):begin_scope(scope)
  end
end

--- Finish the current keymap setup pass, releasing claims it did not renew.
--- @param tabpage number
function M.end_keymap_scope(tabpage)
  local sess = get_active_diffs()[tabpage]
  if sess and sess.keymaps then
    sess.keymaps:end_scope()
  end
end

--- Release every mapping belonging to `scope`.
--- @param tabpage number
--- @param scope string
function M.release_keymap_scope(tabpage, scope)
  local sess = get_active_diffs()[tabpage]
  if sess and sess.keymaps then
    sess.keymaps:release_scope(scope)
  end
end

--- Release a specific mapping the session installed on a buffer.
--- @param tabpage number
--- @param bufnr number
--- @param mode string|string[]
--- @param lhs string|false|nil
function M.del_buf_keymap(tabpage, bufnr, mode, lhs)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    local resolved = keymap.resolve(lhs)
    if resolved and bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      for _, m in ipairs(type(mode) == "table" and mode or { mode }) do
        pcall(vim.keymap.del, m, resolved, { buffer = bufnr })
      end
    end
    return
  end
  sess.keymaps:release(bufnr, mode, lhs)
end

--- Release every mapping the session installed on a buffer that is leaving it.
--- @param tabpage number
--- @param bufnr number
function M.detach_keymap_buffer(tabpage, bufnr)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return
  end
  sess.keymaps:detach_buffer(bufnr)
end

--- Suspend the session's mappings on borrowed (real file) buffers.
--- Called on TabLeave so codediff keys do not appear on those files in other
--- tabs. Panel mappings are registered as non-suspendable and stay installed.
--- @param tabpage number
function M.clear_tab_keymaps(tabpage)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return
  end
  sess.keymaps:suspend()
end

--- Reinstall mappings suspended by clear_tab_keymaps.
--- @param tabpage number
function M.restore_tab_keymaps(tabpage)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return
  end
  sess.keymaps:resume()
end

--- Release every mapping the session installed, handing each key back to
--- whatever owned it before codediff. Idempotent.
--- @param tabpage number
function M.dispose_keymaps(tabpage)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return
  end
  sess.keymaps:dispose()
  sess.keymaps = nil
end

--- Setup auto-sync on file switch: automatically update diff when user edits a different file in working buffer
--- Only activates when one side is virtual (git revision) and other is working file
--- @param tabpage number Tabpage ID
--- @param original_is_virtual boolean Whether original side is virtual (git revision)
--- @param modified_is_virtual boolean Whether modified side is virtual
function M.setup_auto_sync_on_file_switch(tabpage, original_is_virtual, modified_is_virtual)
  -- Only setup if one side is virtual (commit) and other is working file
  if original_is_virtual == modified_is_virtual then
    return -- Both virtual or both real - no sync needed
  end

  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    vim.notify("[codediff] No session found for auto-sync setup", vim.log.levels.ERROR)
    return
  end

  -- Determine which window is working
  local working_win = original_is_virtual and sess.modified_win or sess.original_win
  local working_side = original_is_virtual and "modified" or "original"

  if not working_win or not vim.api.nvim_win_is_valid(working_win) then
    vim.notify("[codediff] Working window not found for auto-sync", vim.log.levels.WARN)
    return
  end

  -- Session stores paths as PathRefs, so read .absolute for identity comparison.
  -- (The old sess[working_side .. "_path"] field is gone and left this nil, which
  -- defeated the change guard below and caused spurious re-updates.)
  local working_ref = sess[working_side]
  local current_path = working_ref and working_ref.absolute or nil

  -- Setup listener using BufWinEnter (fires when buffer enters window, even if existing buffer)
  local sync_group = vim.api.nvim_create_augroup("codediff_working_sync_" .. tabpage, { clear = true })

  -- Listen to BufWinEnter - fires when ANY buffer enters the window (including existing buffers)
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = sync_group,
    callback = function(args)
      -- Check if this buffer is in the working window
      local buf_win = vim.fn.bufwinid(args.buf)
      if buf_win ~= working_win then
        return
      end

      local path = require("codediff.core.path")
      local new_path = vim.api.nvim_buf_get_name(args.buf)

      -- Skip virtual files - they're programmatic, not user navigation
      if new_path:match("^codediff://") then
        return
      end

      -- Normalize to the same absolute form used for the session PathRefs so the
      -- identity comparison is reliable across platforms.
      new_path = new_path ~= "" and path.make_ref(new_path, nil).absolute or ""

      -- Check if file changed
      if new_path == "" or new_path == current_path then
        return
      end

      -- Update tracked path
      current_path = new_path

      -- Path changed! Need to update both sides
      vim.schedule(function()
        -- Get git root (might have changed if user switched to different repo)
        local git = require("codediff.core.git")
        local view = require("codediff.ui.view")

        git.get_git_root(new_path, function(err, new_git_root)
          if err then
            -- Not in git, just update paths without git context
            vim.schedule(function()
              -- Get relative path if possible
              local relative_path = new_path
              if sess.git_root then
                relative_path = git.get_relative_path(new_path, sess.git_root)
              end

              -- No pre-fetching needed, buffers will load content
              view.update(tabpage, {
                mode = sess.mode,
                git_root = nil,
                original = path.make_ref(working_side == "original" and new_path or relative_path, nil),
                modified = path.make_ref(working_side == "modified" and new_path or relative_path, nil),
                original_revision = working_side == "original" and nil or sess.original_revision,
                modified_revision = working_side == "modified" and nil or sess.modified_revision,
              })
            end)
            return
          end

          -- In git! Get relative path
          local relative_path = git.get_relative_path(new_path, new_git_root)

          -- No pre-fetching needed, buffers will load content
          vim.schedule(function()
            view.update(tabpage, {
              mode = sess.mode,
              git_root = new_git_root,
              original = path.make_ref(relative_path, new_git_root),
              modified = path.make_ref(relative_path, new_git_root),
              original_revision = sess.original_revision,
              modified_revision = sess.modified_revision,
            })
          end)
        end)
      end)
    end,
  })
end

return M
