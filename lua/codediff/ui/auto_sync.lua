-- Re-target a diff when the working window switches files.
--
-- Sibling to auto_refresh, which watches buffer *content*. This watches the
-- working window's *file*: when one side of the diff is a git revision and the
-- other is the working file, opening a different file in that window rebuilds
-- the diff around the new file instead of leaving a stale pair on screen.
--
-- Registered per tabpage; the augroup is torn down in lifecycle/cleanup.
local M = {}

-- Lazy require to avoid a cycle: session -> accessors -> ... -> auto_sync
local function get_active_diffs()
  return require("codediff.ui.lifecycle.session").get_active_diffs()
end

--- Setup auto-sync on file switch: automatically update diff when user edits a different file in working buffer
--- Only activates when one side is virtual (git revision) and other is working file
--- @param tabpage number Tabpage ID
--- @param original_is_virtual boolean Whether original side is virtual (git revision)
--- @param modified_is_virtual boolean Whether modified side is virtual
function M.setup(tabpage, original_is_virtual, modified_is_virtual)
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
                panel = sess.panel,
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
              panel = sess.panel,
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
