-- Regression test for c43b1f9: the history .git fs_event handle must be torn
-- down when its callback fires with an error, so a dead watcher (typically the
-- repository being deleted or replaced) does not keep re-delivering errors
-- forever on Windows.
--
-- The watcher lives inside a local closure in `setup_auto_refresh`, so the
-- test stubs `vim.uv.new_fs_event()` with a spy handle, drives the callback
-- with a synthetic error, and asserts that `:stop()` + `:close()` were both
-- invoked on the handle.

local h = dofile("tests/helpers.lua")

describe("History .git watcher teardown on error (c43b1f9)", function()
  local uv = vim.uv or vim.loop
  local original_new_fs_event
  local repo

  before_each(function()
    original_new_fs_event = uv.new_fs_event
    repo = h.create_temp_git_repo()
  end)

  after_each(function()
    uv.new_fs_event = original_new_fs_event
    if repo then
      repo.cleanup()
      repo = nil
    end
  end)

  it("stops and closes the fs_event handle when the watcher callback receives an error", function()
    local calls = { start = 0, stop = 0, close = 0 }
    local captured_callback

    local handle = {}
    function handle:start(_dir, _flags, cb)
      calls.start = calls.start + 1
      captured_callback = cb
      return 0
    end
    function handle:stop()
      calls.stop = calls.stop + 1
      return 0
    end
    function handle:close()
      calls.close = calls.close + 1
    end

    uv.new_fs_event = function()
      return handle
    end

    -- setup_auto_refresh reads history.git_root and history.is_hidden; a
    -- valid tabpage handle is enough for the augroup + tabpage_is_valid check.
    local history = {
      git_root = repo.dir,
      is_hidden = false,
    }
    local tabpage = vim.api.nvim_get_current_tabpage()

    local refresh = require("codediff.ui.history.refresh")
    refresh.setup_auto_refresh(history, tabpage)

    -- The watcher setup is chained through git.get_git_dir + vim.schedule;
    -- wait for the start() to be recorded on the spy before invoking its
    -- callback.
    local started = vim.wait(2000, function()
      return calls.start > 0 and type(captured_callback) == "function"
    end, 20)
    assert.is_true(started, "watcher :start() should have been called")
    assert.equals(1, calls.start)

    -- Fire the callback with a watch error, then let vim.schedule_wrap flush.
    captured_callback("EPERM", nil, nil)
    vim.wait(200)

    assert.equals(1, calls.stop, ":stop() should have been called exactly once on error")
    assert.equals(1, calls.close, ":close() should have been called exactly once on error")

    -- A second callback firing (real Windows symptom: the same error re-fires
    -- forever) must NOT re-trigger stop/close, because the git_watcher local
    -- was nilled by the first error.
    captured_callback("EPERM", nil, nil)
    vim.wait(100)
    assert.equals(1, calls.stop, ":stop() must not be called again after the handle was nilled")
    assert.equals(1, calls.close, ":close() must not be called again after the handle was nilled")

    -- Cleanup the augroup that setup_auto_refresh created.
    if history._cleanup_auto_refresh then
      history._cleanup_auto_refresh()
    end
  end)
end)
