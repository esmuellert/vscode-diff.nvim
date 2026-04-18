-- Auto-refresh and refresh logic for history panel
local M = {}

local git = require("codediff.core.git")
local render_module = require("codediff.ui.history.render")

-- Setup auto-refresh triggers for history panel
-- Returns a cleanup function that should be called when the history is destroyed
function M.setup_auto_refresh(history, tabpage)
  local refresh_timer = nil
  local debounce_ms = 500
  local git_watcher = nil
  local group = vim.api.nvim_create_augroup("CodeDiffHistoryRefresh_" .. tabpage, { clear = true })

  local function cleanup()
    if refresh_timer then
      vim.fn.timer_stop(refresh_timer)
      refresh_timer = nil
    end
    if git_watcher then
      pcall(function()
        git_watcher:stop()
      end)
      pcall(function()
        git_watcher:close()
      end)
      git_watcher = nil
    end
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end

  -- Store cleanup function so lifecycle cleanup can call it
  history._cleanup_auto_refresh = cleanup

  local function debounced_refresh()
    if refresh_timer then
      vim.fn.timer_stop(refresh_timer)
    end
    refresh_timer = vim.fn.timer_start(debounce_ms, function()
      if vim.api.nvim_tabpage_is_valid(tabpage) and not history.is_hidden then
        M.refresh(history)
      end
      refresh_timer = nil
    end)
  end

  -- Watch .git directory for changes
  if history.git_root then
    git.get_git_dir(history.git_root, function(err, git_dir)
      if err or not git_dir then
        return
      end

      vim.schedule(function()
        if vim.fn.isdirectory(git_dir) ~= 1 then
          return
        end

        if not vim.api.nvim_tabpage_is_valid(tabpage) then
          return
        end

        local uv = vim.uv or vim.loop
        git_watcher = uv.new_fs_event()
        if git_watcher then
          local ok = pcall(function()
            git_watcher:start(
              git_dir,
              {},
              vim.schedule_wrap(function(watch_err, filename, events)
                if watch_err then
                  return
                end
                if vim.api.nvim_get_current_tabpage() == tabpage and vim.api.nvim_tabpage_is_valid(tabpage) and not history.is_hidden then
                  debounced_refresh()
                end
              end)
            )
          end)
          if not ok then
            pcall(function()
              git_watcher:close()
            end)
            git_watcher = nil
          end
        end
      end)
    end)
  end

  -- Clean up on tab close
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    pattern = tostring(tabpage),
    callback = cleanup,
  })

  return cleanup
end

-- Refresh history panel with updated commit list
function M.refresh(history)
  if history.is_hidden then
    return
  end

  if not vim.api.nvim_win_is_valid(history.winid) then
    return
  end

  -- Save current cursor position
  local cursor_line = nil
  local ok, pos = pcall(vim.api.nvim_win_get_cursor, history.winid)
  if ok then
    cursor_line = pos[1]
  end

  -- Save which commits were expanded
  local expanded_hashes = {}
  for _, node in ipairs(history.tree:get_nodes() or {}) do
    if node.data and node.data.type == "commit" and node:is_expanded() then
      expanded_hashes[node.data.hash] = true
    end
  end

  -- Reconstruct git log options
  local git_opts = {
    path = history.opts.file_path,
  }
  if history.opts.reverse then
    git_opts.reverse = true
  end
  if history.opts.line_range then
    git_opts.line_range = history.opts.line_range
  end
  if not history.opts.range or history.opts.range == "" then
    git_opts.limit = 100
  end

  local range = history.opts.range or ""

  git.get_commit_list(range, history.git_root, git_opts, function(err, commits)
    if err then
      vim.schedule(function()
        vim.notify("Failed to refresh history: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(history.bufnr) then
        return
      end

      -- Update stored commits
      history.commits = commits

      -- Rebuild tree nodes
      local tree_nodes = render_module.build_tree_nodes(commits, history.git_root, history.opts)

      -- Set new nodes
      history.tree:set_nodes(tree_nodes)

      -- Re-expand previously expanded commits and reload their files
      local has_pending_expand = false
      if history._load_commit_files then
        for _, node in ipairs(history.tree:get_nodes() or {}) do
          if node.data and node.data.type == "commit" and expanded_hashes[node.data.hash] then
            has_pending_expand = true
            history._load_commit_files(node)
          end
        end
      end

      -- Skip render if expanded commits are being reloaded async
      -- (_load_commit_files triggers its own render when files arrive)
      if not has_pending_expand then
        history.tree:render()
      end

      -- Restore cursor position
      if vim.api.nvim_win_is_valid(history.winid) then
        local restored = false
        -- Try to restore to same commit
        if history.current_commit then
          for _, node in ipairs(history.tree:get_nodes() or {}) do
            if node.data and node.data.hash == history.current_commit and node._line then
              pcall(vim.api.nvim_win_set_cursor, history.winid, { node._line, 0 })
              restored = true
              break
            end
          end
        end
        -- Fall back to same line number
        if not restored and cursor_line then
          local line_count = vim.api.nvim_buf_line_count(history.bufnr)
          local target_line = math.min(cursor_line, line_count)
          pcall(vim.api.nvim_win_set_cursor, history.winid, { target_line, 0 })
        end
      end
    end)
  end)
end

return M
