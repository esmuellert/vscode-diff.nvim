-- Serializes complete Explorer refresh cycles across every request source.
local M = {}

local config = require("codediff.config")

function M.setup(explorer, tabpage, refresh_once)
  local explorer_config = config.options.explorer or {}
  local uv = vim.uv or vim.loop
  local poll_timer
  local unsubscribe
  local cleaned = false
  local refresh_running = false
  local refresh_pending = false
  local pending_force = false
  local pending_done = {}
  local group

  local function stop_polling()
    if not poll_timer then
      return
    end
    pcall(function()
      poll_timer:stop()
    end)
    pcall(function()
      poll_timer:close()
    end)
    poll_timer = nil
  end

  local function cleanup()
    if cleaned then
      return
    end
    cleaned = true
    stop_polling()
    if unsubscribe then
      unsubscribe()
      unsubscribe = nil
    end
    pending_done = {}
    explorer._request_refresh = nil
    explorer._request_auto_refresh = nil
    explorer._native_watcher_ready = nil
    if group then
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end
  end

  explorer._cleanup_auto_refresh = cleanup

  local function call_done(callbacks)
    for _, callback in ipairs(callbacks) do
      pcall(callback)
    end
  end

  local request_refresh
  request_refresh = function(force, done_callbacks)
    done_callbacks = done_callbacks or {}
    if cleaned then
      return
    end
    if refresh_running then
      refresh_pending = true
      pending_force = pending_force or force == true
      vim.list_extend(pending_done, done_callbacks)
      return
    end
    refresh_running = true
    refresh_once(explorer, function()
      if cleaned then
        return
      end
      require("codediff.ui.auto_refresh").sync_mutable_buffers(tabpage, function()
        if cleaned then
          return
        end
        refresh_running = false
        call_done(done_callbacks)
        if refresh_pending then
          local force_pending = pending_force
          local done_pending = pending_done
          refresh_pending = false
          pending_force = false
          pending_done = {}
          request_refresh(force_pending, done_pending)
        end
      end)
    end, force)
  end

  local function tick(force)
    if not vim.api.nvim_tabpage_is_valid(tabpage) or explorer.is_hidden then
      return
    end
    -- A queued fallback tick may outlive the tab or repository setup/teardown.
    local git_root = explorer.git_root
    if git_root and git_root ~= "" then
      if vim.fn.isdirectory(git_root) == 0 then
        return
      end
      -- Linked worktrees and submodules use a .git pointer file.
      local dot_git = git_root .. "/.git"
      if vim.fn.isdirectory(dot_git) == 0 and vim.fn.filereadable(dot_git) == 0 then
        return
      end
    end
    request_refresh(force)
  end

  explorer._request_refresh = function(force, done)
    request_refresh(force, done and { done } or {})
  end
  explorer._request_auto_refresh = function()
    tick(true)
  end

  if explorer_config.auto_refresh == false then
    return cleanup
  end

  group = vim.api.nvim_create_augroup("CodeDiffExplorerRefresh_" .. tabpage, { clear = true })

  local function start_polling()
    if cleaned or poll_timer then
      return
    end
    poll_timer = uv.new_timer()
    if poll_timer then
      poll_timer:start(500, 500, vim.schedule_wrap(tick))
    end
  end

  start_polling()
  if explorer.git_root and explorer.git_root ~= "" then
    unsubscribe = require("codediff.core.watcher").subscribe(explorer.git_root, {
      on_ready = function()
        explorer._native_watcher_ready = true
        stop_polling()
        tick(true)
      end,
      on_refresh = function()
        tick(true)
      end,
      on_error = function()
        explorer._native_watcher_ready = false
        start_polling()
      end,
    })
  end

  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    pattern = tostring(tabpage),
    callback = cleanup,
  })

  return cleanup
end

return M
