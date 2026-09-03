describe("explorer native watcher", function()
  local uv = vim.uv or vim.loop
  local original_new_timer
  local original_watcher
  local original_auto_refresh
  local refresh_module
  local original_refresh
  local cleanup
  local repository
  local watcher_handlers
  local unsubscribed
  local timers
  local refresh_completions
  local refresh_forces
  local refresh_count
  local sync_count
  local sync_completions

  before_each(function()
    repository = vim.fn.tempname()
    vim.fn.mkdir(repository .. "/.git", "p")
    timers = {}
    refresh_completions = {}
    refresh_forces = {}
    refresh_count = 0
    sync_count = 0
    sync_completions = {}
    unsubscribed = false

    original_new_timer = uv.new_timer
    uv.new_timer = function()
      local timer = { started = false, stopped = false, closed = false }
      function timer:start(_, _, callback)
        self.started = true
        self.callback = callback
      end
      function timer:stop()
        self.stopped = true
      end
      function timer:close()
        self.closed = true
      end
      function timer:is_closing()
        return self.closed
      end
      timers[#timers + 1] = timer
      return timer
    end

    original_watcher = package.loaded["codediff.core.watcher"]
    package.loaded["codediff.core.watcher"] = {
      subscribe = function(root, handlers)
        assert.equals(repository, root)
        watcher_handlers = handlers
        return function()
          unsubscribed = true
        end
      end,
    }

    original_auto_refresh = package.loaded["codediff.ui.auto_refresh"]
    package.loaded["codediff.ui.auto_refresh"] = {
      sync_mutable_buffers = function(_, done)
        sync_count = sync_count + 1
        sync_completions[#sync_completions + 1] = done
      end,
    }

    refresh_module = require("codediff.ui.explorer.refresh")
    original_refresh = refresh_module._refresh_once
    refresh_module._refresh_once = function(_, done, force)
      refresh_count = refresh_count + 1
      refresh_completions[#refresh_completions + 1] = done
      refresh_forces[#refresh_forces + 1] = force == true
    end
  end)

  after_each(function()
    if cleanup then
      cleanup()
      cleanup = nil
    end
    refresh_module._refresh_once = original_refresh
    package.loaded["codediff.core.watcher"] = original_watcher
    package.loaded["codediff.ui.auto_refresh"] = original_auto_refresh
    uv.new_timer = original_new_timer
    vim.fn.delete(repository, "rf")
  end)

  local function setup()
    local tabpage = vim.api.nvim_get_current_tabpage()
    local explorer = {
      git_root = repository,
      is_hidden = false,
      winid = vim.api.nvim_get_current_win(),
    }
    cleanup = refresh_module.setup_auto_refresh(explorer, tabpage)
    return explorer
  end

  it("stops polling after ready and serializes refreshes", function()
    local explorer = setup()
    assert.equals(1, #timers)
    assert.is_true(timers[1].started)

    watcher_handlers.on_ready()
    assert.is_true(explorer._native_watcher_ready)
    assert.is_true(timers[1].stopped)
    assert.is_true(timers[1].closed)
    assert.equals(1, refresh_count)
    assert.is_true(refresh_forces[1])

    local direct_completed = 0
    watcher_handlers.on_refresh()
    watcher_handlers.on_refresh()
    refresh_module.refresh(explorer, function()
      direct_completed = direct_completed + 1
    end)
    watcher_handlers.on_refresh()
    assert.equals(1, refresh_count)
    assert.is_true(refresh_forces[1])

    refresh_completions[1]()
    assert.equals(1, sync_count)
    assert.equals(1, refresh_count)

    sync_completions[1]()
    assert.equals(2, refresh_count)
    assert.equals(0, direct_completed)
    assert.is_true(refresh_forces[2])

    refresh_completions[2]()
    assert.equals(2, sync_count)
    assert.equals(2, refresh_count)
    sync_completions[2]()
    assert.equals(1, direct_completed)
  end)

  it("keeps status-equality shortcuts for fallback polling", function()
    setup()
    timers[1].callback()
    assert.is_true(vim.wait(1000, function()
      return refresh_count == 1
    end, 10))
    assert.is_false(refresh_forces[1])
    refresh_completions[1]()
    sync_completions[1]()
  end)

  it("drops a trailing refresh when cleanup happens during mutable sync", function()
    setup()
    watcher_handlers.on_ready()
    watcher_handlers.on_refresh()
    refresh_completions[1]()

    assert.equals(1, sync_count)
    cleanup()
    cleanup = nil
    sync_completions[1]()

    assert.equals(1, refresh_count)
    assert.is_true(unsubscribed)
  end)

  it("returns to polling after a running watcher fails", function()
    local explorer = setup()
    watcher_handlers.on_ready()
    watcher_handlers.on_error("process exited")

    assert.is_false(explorer._native_watcher_ready)

    assert.equals(2, #timers)
    assert.is_true(timers[2].started)

    cleanup()
    cleanup = nil
    assert.is_true(timers[2].stopped)
    assert.is_true(timers[2].closed)
    assert.is_true(unsubscribed)
  end)

  it("requests a refresh when a hidden explorer is shown again", function()
    local explorer = setup()
    explorer.is_hidden = true
    watcher_handlers.on_ready()
    watcher_handlers.on_refresh()
    assert.equals(0, refresh_count)

    explorer.is_hidden = false
    explorer._request_auto_refresh()
    assert.equals(1, refresh_count)
  end)
end)
