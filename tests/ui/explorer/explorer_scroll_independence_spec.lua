-- Regression: the explorer pane must NOT scroll together with the side-by-side
-- diff panes. With native scrollbind this could happen if the explorer window
-- ever inherited scrollbind=true. codediff's structural scroll-sync only ever
-- binds the explicit diff windows, so the explorer is always independent.

local h = dofile("tests/helpers.lua")

-- Ensure plugin is loaded (registers the :CodeDiff command for the subprocess).
h.ensure_plugin_loaded()

local function setup_command()
  local commands = require("codediff.commands")
  vim.api.nvim_create_user_command("CodeDiff", function(opts)
    commands.vscode_diff(opts)
  end, { nargs = "*", bang = true })
end

-- Repo with a long first file (so the diff panes can scroll a lot) plus many
-- small changed files (so the explorer list is longer than the window and can
-- itself scroll). Returns the repo handle.
local function busy_repo()
  local repo = h.create_temp_git_repo()
  local long = {}
  for i = 1, 200 do
    long[i] = string.format("line %03d", i)
  end
  repo.write_file("file01.txt", long)
  for n = 2, 40 do
    repo.write_file(string.format("file%02d.txt", n), { "a", "b" })
  end
  repo.git("add -A")
  repo.git('commit -m "initial"')
  local longmod = vim.deepcopy(long)
  longmod[5] = "CHANGED 005"
  longmod[150] = "CHANGED 150"
  repo.write_file("file01.txt", longmod)
  for n = 2, 40 do
    repo.write_file(string.format("file%02d.txt", n), { "A", "b" })
  end
  return repo
end

local function open_codediff_and_wait(repo, timeout_ms)
  timeout_ms = timeout_ms or 12000
  vim.fn.chdir(repo.dir)
  vim.cmd("edit " .. repo.path("file01.txt"))
  vim.cmd("CodeDiff")
  local lifecycle = require("codediff.ui.lifecycle")
  local scroll = require("codediff.ui.scroll")
  local tabpage
  -- Wait until the diff content has loaded AND the scroll-sync group is bound
  -- (both happen asynchronously after :CodeDiff).
  local ready = vim.wait(timeout_ms, function()
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
      local s = lifecycle.get_session(tp)
      if s and s.explorer and s.modified_win and vim.api.nvim_win_is_valid(s.modified_win) then
        local mbuf = vim.api.nvim_win_get_buf(s.modified_win)
        if vim.api.nvim_buf_is_valid(mbuf) and vim.api.nvim_buf_line_count(mbuf) > 100 and scroll.get(tp) then
          tabpage = tp
          return true
        end
      end
    end
    return false
  end, 100)
  assert.is_true(ready, "CodeDiff explorer, loaded diff panes, and scroll-sync group should be ready")
  local session = lifecycle.get_session(tabpage)
  return tabpage, session, session.explorer
end

local function topline(win)
  return vim.api.nvim_win_call(win, function()
    return vim.fn.line("w0")
  end)
end

describe("explorer scroll independence", function()
  local repo
  before_each(function()
    require("codediff").setup()
    setup_command()
  end)
  after_each(function()
    if repo then
      repo.cleanup()
      repo = nil
    end
    pcall(function()
      while vim.fn.tabpagenr("$") > 1 do
        vim.cmd("tabclose!")
      end
    end)
  end)

  it("keeps the explorer out of the diff scroll-sync group", function()
    repo = busy_repo()
    local tabpage, _, explorer = open_codediff_and_wait(repo)
    assert.is_not_nil(explorer and explorer.winid, "explorer window should exist")

    local scroll = require("codediff.ui.scroll")
    local group = scroll.get(tabpage)
    assert.is_not_nil(group, "a scroll-sync group should exist for the diff")
    for _, w in ipairs(group.wins) do
      assert.are_not.equal(explorer.winid, w, "explorer must not be in the scroll-sync group")
    end
    assert.is_false(vim.wo[explorer.winid].scrollbind, "explorer must not have native scrollbind")
  end)

  it("does not move the explorer when the diff panes scroll", function()
    repo = busy_repo()
    local _, session, explorer = open_codediff_and_wait(repo)
    local explorer_top_before = topline(explorer.winid)
    local orig_top_before = topline(session.original_win)

    vim.api.nvim_set_current_win(session.modified_win)
    vim.api.nvim_win_set_cursor(session.modified_win, { 1, 0 })
    for _ = 1, 80 do
      vim.cmd("normal! \5") -- <C-e>
    end
    -- Headless has no UI, so WinScrolled does not fire on its own; fire it so
    -- the scroll-sync actually runs (as it would with a real UI).
    vim.api.nvim_exec_autocmds("WinScrolled", {})
    vim.cmd("redraw")

    assert.is_true(topline(session.modified_win) > 20, "modified diff pane should have scrolled down")
    -- The other diff pane DOES follow (sync is live)...
    assert.is_true(topline(session.original_win) > orig_top_before, "original diff pane should follow (sync live)")
    -- ...but the explorer must stay put.
    assert.are.equal(explorer_top_before, topline(explorer.winid), "explorer must stay put while the diff panes scroll")
  end)

  it("does not move the diff panes when the explorer scrolls", function()
    repo = busy_repo()
    local _, session, explorer = open_codediff_and_wait(repo)

    -- Move the diff to a non-top position first.
    vim.api.nvim_set_current_win(session.modified_win)
    vim.api.nvim_win_set_cursor(session.modified_win, { 1, 0 })
    for _ = 1, 40 do
      vim.cmd("normal! \5")
    end
    vim.api.nvim_exec_autocmds("WinScrolled", {})
    vim.cmd("redraw")
    local mod_top = topline(session.modified_win)
    local orig_top = topline(session.original_win)

    -- Scroll the explorer and fire WinScrolled; the diff panes must not move.
    vim.api.nvim_set_current_win(explorer.winid)
    vim.api.nvim_win_set_cursor(explorer.winid, { 1, 0 })
    for _ = 1, 20 do
      vim.cmd("normal! \5")
    end
    vim.api.nvim_exec_autocmds("WinScrolled", {})
    vim.cmd("redraw")

    assert.are.equal(mod_top, topline(session.modified_win), "modified diff pane must stay put while the explorer scrolls")
    assert.are.equal(orig_top, topline(session.original_win), "original diff pane must stay put while the explorer scrolls")
  end)
end)
