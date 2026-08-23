-- Two independent explorer regressions, both fixed in the file-refresh path.
--
-- 1. Idle refresh loop: the explorer watches .git to notice external changes,
--    but its own `git status` momentarily writes .git/index.lock, which woke
--    the watcher and triggered another status, indefinitely (~2 refreshes/sec
--    while completely idle). The watcher now ignores *.lock events.
--
-- 2. Single-file resize reset: untracked/added/deleted files render in a single
--    pane via show_single_file. A refresh re-selects the open file; real
--    two-pane diffs short-circuit that, but the single-file statuses rebuilt
--    the window every time and the layout pass discarded any manual sizing.
--    show_single_file now skips the rebuild when nothing changed.
--
-- Split from tests/ui/explorer/explorer_spec.lua so the two describe blocks
-- (one for open/layout, one for refresh) can run as independent workers under
-- the framework's per-file parallelism.

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

  local function open(focus_file)
    local lifecycle = require("codediff.ui.lifecycle")
    lifecycle.cleanup_all()
    vim.cmd("edit " .. temp_dir .. "/" .. focus_file)
    vim.cmd("CodeDiff")
    local tabpage, explorer
    local ready = vim.wait(10000, function()
      for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
        local e = lifecycle.get_explorer(tp)
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
    if original_get_status_with_line_stats then
      require("codediff.core.git").get_status_with_line_stats = original_get_status_with_line_stats
      original_get_status_with_line_stats = nil
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

  it("polls at a bounded, deterministic cadence while idle", function()
    -- The old .git/ watcher self-triggered off its own index.lock writes at
    -- roughly 2 refreshes/second — an accidental loop, not a designed cadence.
    -- #480 killed that loop with a `*.lock` filter, but the filter also
    -- suppressed events for external working-tree changes (e.g. `touch`
    -- from another terminal), so those stopped surfacing until the user
    -- refocused the explorer. The current design is an explicit 500ms poll:
    -- same detection latency, deterministic idle cost, no self-triggering.
    -- This test guards the *polling contract*: the tick fires steadily and
    -- doesn't drift wildly (either much faster, i.e. a self-trigger loop
    -- returning, or much slower, i.e. the timer stopping).
    local refresh_module = require("codediff.ui.explorer.refresh")
    local _, explorer = open("file1.txt")
    select_and_settle(explorer, "file1.txt", "M", "unstaged", { force = true })
    vim.wait(1500, function()
      return false
    end)

    local count = 0
    local orig = refresh_module.refresh
    refresh_module.refresh = function(e)
      count = count + 1
      return orig(e)
    end
    vim.wait(4000, function()
      return false
    end)
    refresh_module.refresh = orig

    -- Expected ~8 refreshes at 500ms cadence over 4s; allow a generous window
    -- for scheduler jitter and coalesced ticks.
    assert.is_true(count >= 5, "poll must actually tick, got " .. count)
    assert.is_true(count <= 12, "poll must not exceed the 500ms cadence, got " .. count)
  end)

  it("coalesces overlapping refreshes into one follow-up", function()
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
    local callbacks = {}
    local calls = 0
    git.get_status_with_line_stats = function(_, callback)
      calls = calls + 1
      callbacks[calls] = callback
    end

    refresh.refresh(explorer)
    refresh.refresh(explorer)
    refresh.refresh(explorer)
    assert.are.equal(1, calls, "overlapping refreshes must share one Git scan")

    callbacks[1](nil, vim.deepcopy(explorer.status_result))
    refresh.refresh(explorer)
    assert.are.equal(1, calls, "refresh must stay serialized until result processing finishes")
    assert.is_true(
      vim.wait(1000, function()
        return calls == 2
      end, 20),
      "overlap should schedule one follow-up scan"
    )

    callbacks[2](nil, vim.deepcopy(explorer.status_result))
    vim.wait(100, function()
      return false
    end)
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
    -- Regression guard for the post-#480 behavior: after #480 killed the
    -- .git/ watcher's self-triggering loop with a `*.lock` filter, external
    -- working-tree changes (a `touch` from another terminal) stopped surfacing
    -- until the user refocused the explorer. The polling replacement restores
    -- automatic detection.
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
