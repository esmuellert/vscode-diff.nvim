-- Explorer polling, refresh serialization, external-change detection, and
-- single-file layout stability.

local config = require("codediff.config")
local h = dofile("tests/helpers.lua")

-- Setup CodeDiff command for tests
local function setup_command()
  local commands = require("codediff.commands")
  vim.api.nvim_create_user_command("CodeDiff", function(opts)
    commands.vscode_diff(opts)
  end, {
    nargs = "*",
    bang = true,
    complete = function()
      return { "file", "install" }
    end,
  })
end

describe("Explorer refresh and single-file stability", function()
  local temp_dir
  local original_cwd
  local original_get_status_with_line_stats
  local original_new_timer
  local original_refresh
  local original_sync_mutable_buffers

  local function open(focus_file)
    local lifecycle = require("codediff.ui.lifecycle")
    lifecycle.cleanup_all()
    vim.cmd("edit " .. temp_dir .. "/" .. focus_file)
    vim.cmd("CodeDiff")
    local tabpage, explorer
    local ready = vim.wait(10000, function()
      for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local e = lifecycle.get_panel_view(tp)
        if e and e.winid and vim.api.nvim_win_is_valid(e.winid) then
          tabpage, explorer = tp, e
          return true
        end
      end
      return false
    end, 50)
    assert.is_true(ready, "explorer should open")
    return tabpage, explorer
  end

  local function select_and_settle(explorer, path, status, group, opts)
    explorer.on_file_select({ path = path, status = status, group = group, git_root = temp_dir }, opts or {})
    vim.wait(2500, function()
      return false
    end)
  end

  local function single_win(tabpage)
    local lifecycle = require("codediff.ui.lifecycle")
    local s = lifecycle.get_session(tabpage)
    if s.original_win and vim.api.nvim_win_is_valid(s.original_win) then
      return s.original_win
    end
    if s.modified_win and vim.api.nvim_win_is_valid(s.modified_win) then
      return s.modified_win
    end
  end

  before_each(function()
    config.options = vim.deepcopy(config.defaults)
    require("codediff").setup({ diff = { layout = "side-by-side" } })
    setup_command()
    original_cwd = vim.fn.getcwd()
    temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    vim.fn.chdir(temp_dir)
    h.git_cmd(temp_dir, "init")
    h.git_cmd(temp_dir, "branch -m main")
    h.git_cmd(temp_dir, 'config user.email "test@example.com"')
    h.git_cmd(temp_dir, 'config user.name "Test User"')
    vim.fn.writefile({ "line 1", "line 2" }, temp_dir .. "/file1.txt")
    h.git_cmd(temp_dir, "add file1.txt")
    h.git_cmd(temp_dir, 'commit -m "initial"')
    -- file1.txt modified (unstaged), file3.txt untracked
    vim.fn.writefile({ "line 1", "line 2 modified" }, temp_dir .. "/file1.txt")
    vim.fn.writefile({ "untracked" }, temp_dir .. "/file3.txt")
  end)

  after_each(function()
    if original_new_timer then
      local uv = vim.uv or vim.loop
      uv.new_timer = original_new_timer
      original_new_timer = nil
    end
    if original_refresh then
      require("codediff.ui.explorer.refresh").refresh = original_refresh
      original_refresh = nil
    end
    if original_get_status_with_line_stats then
      require("codediff.core.git").get_status_with_line_stats = original_get_status_with_line_stats
      original_get_status_with_line_stats = nil
    end
    if original_sync_mutable_buffers then
      require("codediff.ui.auto_refresh").sync_mutable_buffers = original_sync_mutable_buffers
      original_sync_mutable_buffers = nil
    end
    require("codediff.ui.lifecycle").cleanup_all()
    vim.cmd("tabnew")
    vim.cmd("tabonly")
    vim.fn.chdir(original_cwd)
    vim.wait(200)
    if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  it("accepts boolean and numeric auto-refresh settings", function()
    local refresh = require("codediff.ui.explorer.refresh")
    local uv = vim.uv or vim.loop
    local started
    original_new_timer = uv.new_timer
    uv.new_timer = function()
      return {
        start = function(_, timeout, interval)
          started = { timeout = timeout, interval = interval }
        end,
        stop = function() end,
        close = function() end,
      }
    end

    config.options.explorer.auto_refresh = true
    local default_explorer = {}
    refresh.setup_auto_refresh(default_explorer, vim.api.nvim_get_current_tabpage())
    assert.are.same({ timeout = 500, interval = 500 }, started)
    default_explorer._cleanup_auto_refresh()

    started = nil
    config.options.explorer.auto_refresh = 1250
    local custom_explorer = {}
    refresh.setup_auto_refresh(custom_explorer, vim.api.nvim_get_current_tabpage())
    assert.are.same({ timeout = 1250, interval = 1250 }, started)
    custom_explorer._cleanup_auto_refresh()

    started = nil
    config.options.explorer.auto_refresh = false
    local disabled_explorer = {}
    refresh.setup_auto_refresh(disabled_explorer, vim.api.nvim_get_current_tabpage())
    assert.is_nil(started)
    assert.is_function(disabled_explorer._cleanup_auto_refresh)
    disabled_explorer._cleanup_auto_refresh()
  end)

  it("rejects invalid auto-refresh settings", function()
    local refresh = require("codediff.ui.explorer.refresh")
    for _, value in ipairs({ 0, -1, 1.5, "false", {} }) do
      config.options.explorer.auto_refresh = value
      local ok, err = pcall(refresh.setup_auto_refresh, {}, vim.api.nvim_get_current_tabpage())
      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("positive integer", 1, true))
    end
  end)

  it("polls at a bounded, deterministic cadence while idle", function()
    local refresh_module = require("codediff.ui.explorer.refresh")
    local _, explorer = open("file1.txt")
    select_and_settle(explorer, "file1.txt", "M", "unstaged", { force = true })
    vim.wait(1500, function()
      return false
    end)

    local count = 0
    original_refresh = refresh_module.refresh
    refresh_module.refresh = function(e)
      count = count + 1
      return original_refresh(e)
    end
    vim.wait(4000, function()
      return false
    end)
    refresh_module.refresh = original_refresh
    original_refresh = nil

    -- Expected ~8 refreshes at 500ms cadence over 4s; allow a generous window
    -- for scheduler jitter and coalesced ticks.
    assert.is_true(count >= 5, "poll must actually tick, got " .. count)
    assert.is_true(count <= 12, "poll must not exceed the 500ms cadence, got " .. count)
  end)

  it("coalesces overlapping refreshes into one follow-up", function()
    local refresh = require("codediff.ui.explorer.refresh")
    local auto_refresh = require("codediff.ui.auto_refresh")
    local git = require("codediff.core.git")
    local _, explorer = open("file1.txt")
    select_and_settle(explorer, "file1.txt", "M", "unstaged", { force = true })
    assert.is_true(
      vim.wait(3000, function()
        return explorer._refresh_in_flight ~= true
      end, 50),
      "initial refresh should settle"
    )

    original_get_status_with_line_stats = git.get_status_with_line_stats
    original_sync_mutable_buffers = auto_refresh.sync_mutable_buffers
    local callbacks = {}
    local sync_callbacks = {}
    local calls = 0
    local sync_calls = 0
    git.get_status_with_line_stats = function(_, callback)
      calls = calls + 1
      callbacks[calls] = callback
    end
    auto_refresh.sync_mutable_buffers = function(_, callback)
      sync_calls = sync_calls + 1
      sync_callbacks[sync_calls] = callback
    end

    refresh.refresh(explorer)
    refresh.refresh(explorer)
    refresh.refresh(explorer)
    assert.are.equal(1, calls, "overlapping refreshes must share one Git scan")

    callbacks[1](nil, vim.deepcopy(explorer.status_result))
    assert.is_true(
      vim.wait(1000, function()
        return sync_calls == 1
      end, 20),
      "mutable buffer sync should start after status processing"
    )
    refresh.refresh(explorer)
    assert.are.equal(1, calls, "refresh must stay serialized until mutable buffers settle")

    sync_callbacks[1]()
    assert.is_true(
      vim.wait(1000, function()
        return calls == 2
      end, 20),
      "overlap should schedule one follow-up scan"
    )

    callbacks[2](nil, vim.deepcopy(explorer.status_result))
    assert.is_true(vim.wait(1000, function()
      return sync_calls == 2
    end, 20))
    sync_callbacks[2]()
    assert.is_true(vim.wait(1000, function()
      return explorer._refresh_in_flight == false
    end, 20))
    assert.are.equal(2, calls, "multiple overlaps must coalesce into one follow-up")
  end)

  it("drops pending refreshes when the explorer is closed", function()
    local refresh = require("codediff.ui.explorer.refresh")
    local git = require("codediff.core.git")
    local _, explorer = open("file1.txt")
    select_and_settle(explorer, "file1.txt", "M", "unstaged", { force = true })
    assert.is_true(
      vim.wait(3000, function()
        return explorer._refresh_in_flight ~= true
      end, 50),
      "initial refresh should settle"
    )

    original_get_status_with_line_stats = git.get_status_with_line_stats
    local callback
    local calls = 0
    git.get_status_with_line_stats = function(_, cb)
      calls = calls + 1
      callback = cb
    end

    refresh.refresh(explorer)
    refresh.refresh(explorer)
    assert.are.equal(1, calls)

    require("codediff.ui.lifecycle").cleanup_all()
    callback(nil, vim.deepcopy(explorer.status_result))
    vim.wait(100, function()
      return false
    end)

    assert.are.equal(1, calls, "cleanup must cancel the pending follow-up")
    assert.is_false(explorer._refresh_in_flight)
    assert.is_false(explorer._refresh_pending)
  end)

  it("picks up an externally-created untracked file automatically", function()
    local _, explorer = open("file1.txt")
    select_and_settle(explorer, "file1.txt", "M", "unstaged", { force = true })
    vim.wait(800, function()
      return false
    end)

    -- External change: brand-new untracked file, no nvim buffer, no BufEnter.
    vim.fn.writefile({ "hello from outside" }, temp_dir .. "/brand_new.txt")

    -- Wait for the poll to notice.
    local picked_up = vim.wait(3000, function()
      for _, f in ipairs((explorer.status_result or {}).unstaged or {}) do
        if f.path == "brand_new.txt" then
          return true
        end
      end
      return false
    end, 100)
    assert.is_true(picked_up, "external file must appear in the explorer without focus")
  end)

  it("keeps a manually resized single-file pane across a refresh", function()
    local tabpage, explorer = open("file1.txt")
    select_and_settle(explorer, "file3.txt", "??", "unstaged", { force = true })

    local win = single_win(tabpage)
    assert.is_not_nil(win, "untracked file should be shown in a single pane")
    local width = vim.api.nvim_win_get_width(win) - 10
    vim.api.nvim_win_call(win, function()
      vim.cmd("vertical resize " .. width)
    end)
    assert.are.equal(width, vim.api.nvim_win_get_width(win), "resize should apply")

    -- A refresh re-selects the file that is already open.
    select_and_settle(explorer, "file3.txt", "??", "unstaged")

    assert.are.equal(width, vim.api.nvim_win_get_width(single_win(tabpage)), "manual pane size must survive a refresh")
  end)

  it("still re-renders a single-file view when the file's status changes", function()
    local tabpage, explorer = open("file1.txt")
    select_and_settle(explorer, "file3.txt", "??", "unstaged", { force = true })
    local before = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(single_win(tabpage)))

    -- Staging turns ?? into A, shown from the index (:0) rather than the working
    -- tree, so the view must rebuild rather than be skipped.
    h.git_cmd(temp_dir, "add file3.txt")
    select_and_settle(explorer, "file3.txt", "A", "staged")

    local after = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(single_win(tabpage)))
    assert.are_not.equal(before, after, "staged view must come from a different buffer than the working-tree view")
  end)

  it("still restores both panes when returning to a real diff", function()
    local tabpage, explorer = open("file1.txt")
    select_and_settle(explorer, "file3.txt", "??", "unstaged", { force = true })
    assert.is_not_nil(single_win(tabpage), "should be in single-pane mode")

    select_and_settle(explorer, "file1.txt", "M", "unstaged", { force = true })

    local lifecycle = require("codediff.ui.lifecycle")
    local s = lifecycle.get_session(tabpage)
    assert.is_true(
      s.original_win ~= nil and vim.api.nvim_win_is_valid(s.original_win) and s.modified_win ~= nil and vim.api.nvim_win_is_valid(s.modified_win),
      "returning to a modified file must restore both diff panes"
    )
  end)
end)
