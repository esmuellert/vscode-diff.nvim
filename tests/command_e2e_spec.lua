-- End-to-end coverage of the :CodeDiff command grammars. Each case triggers the
-- real command in a real temp git repo and asserts the actual rendered result
-- (diff buffer contents, explorer file list, history commits, layout) — not just
-- that dispatch routed correctly.
--
-- Scope note: the plenary harness cannot drive the async codediff:// virtual-file
-- load (git-show for a revision) — a diff whose original is a git *revision*
-- opens a tab but never finishes registering its session under the test runner
-- (it works fine interactively; see scripts/nvim-e2e.lua). So the git-revision
-- single-file diffs (`file HEAD`, `file <rev> <rev>`) and 3-way `merge` are not
-- asserted here; their dispatch is covered by tests/core/argparse_spec.lua and
-- the command-parity differential. The single-file diff *render* and the layout
-- flags are still covered below using two real files (no virtual buffer).

local h = dofile("tests/helpers.lua")
local lifecycle = require("codediff.ui.lifecycle")
local commands = require("codediff.commands")

describe("Command E2E (real dispatch + render)", function()
  local repo
  local hash1, hash2

  local function setup_command()
    vim.api.nvim_create_user_command("CodeDiff", function(opts)
      commands.vscode_diff(opts)
    end, { nargs = "*", bang = true, range = true })
  end

  local function find_explorer_buf()
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "codediff-explorer" then
          return buf
        end
      end
    end
  end

  local function explorer_text(timeout)
    vim.wait(timeout or 10000, function()
      return find_explorer_buf() ~= nil
    end, 50)
    local buf = find_explorer_buf()
    assert.is_not_nil(buf, "an explorer window should open")
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  end

  local function session_tabs()
    local out = {}
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
      if lifecycle.get_session(tp) then
        out[#out + 1] = tp
      end
    end
    return out
  end

  -- Wait for a diff session (real-file diff) whose buffers contain `text`.
  local function wait_for_diff_text(text, timeout)
    local found
    vim.wait(timeout or 10000, function()
      for _, tp in ipairs(session_tabs()) do
        local o, m = lifecycle.get_buffers(tp)
        for _, b in ipairs({ o, m }) do
          if b and vim.api.nvim_buf_is_valid(b) then
            if table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n"):find(text, 1, true) then
              found = tp
              return true
            end
          end
        end
      end
      return false
    end, 50)
    return found
  end

  local function all_visible_text()
    local chunks = {}
    for _, tp in ipairs(vim.api.nvim_list_tabpages()) do
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tp)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) then
          table.insert(chunks, table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
        end
      end
    end
    return table.concat(chunks, "\n")
  end

  local function wait_for_visible(text, timeout)
    return vim.wait(timeout or 10000, function()
      return all_visible_text():find(text, 1, true) ~= nil
    end, 50)
  end

  before_each(function()
    setup_command()
    repo = h.create_temp_git_repo()
    repo.write_file("file.txt", { "line 1", "line 2", "line 3" })
    repo.git("add file.txt")
    repo.git("commit -m c1")
    hash1 = vim.trim((repo.git("rev-parse HEAD")))
    repo.write_file("file.txt", { "line 1", "line 2 CHANGED", "line 3" })
    repo.git("add file.txt")
    repo.git("commit -m c2")
    hash2 = vim.trim((repo.git("rev-parse HEAD")))
    repo.write_file("a.txt", { "alpha content", "shared" })
    repo.write_file("b.txt", { "beta content", "shared" })
    vim.cmd("edit " .. repo.path("file.txt"))
  end)

  after_each(function()
    for _, tp in ipairs(session_tabs()) do
      pcall(lifecycle.close, tp)
    end
    vim.wait(150)
    vim.cmd("silent! tabnew")
    vim.cmd("silent! tabonly")
    vim.cmd("silent! enew")
    vim.wait(100)
    if repo then
      repo.cleanup()
    end
  end)

  -- ── Explorer family ───────────────────────────────────────────────────────

  it(":CodeDiff — explorer lists working-tree changes", function()
    repo.write_file("file.txt", { "line 1", "line 2 WORKING", "line 3" })
    vim.cmd("edit! " .. repo.path("file.txt"))
    vim.cmd("CodeDiff")
    h.assert_contains(explorer_text(), "file.txt", "explorer lists file.txt")
  end)

  it(":CodeDiff HEAD~1 — explorer against a revision", function()
    vim.cmd("CodeDiff HEAD~1")
    h.assert_contains(explorer_text(), "file.txt")
  end)

  it(":CodeDiff <rev1> <rev2> — explorer comparing two revisions", function()
    vim.cmd("CodeDiff " .. hash1 .. " " .. hash2)
    h.assert_contains(explorer_text(), "file.txt")
  end)

  it(":CodeDiff main... — merge-base explorer shows only branch changes", function()
    repo.git("checkout -b feature " .. hash1)
    repo.write_file("feature.txt", { "feature work" })
    repo.git("add feature.txt")
    repo.git("commit -m feat")
    vim.cmd("CodeDiff main...")
    h.assert_contains(explorer_text(), "feature.txt")
  end)

  -- ── Single-file diff (two real files) ─────────────────────────────────────

  it(":CodeDiff file <a> <b> — renders both files in a diff", function()
    vim.cmd("CodeDiff file " .. repo.path("a.txt") .. " " .. repo.path("b.txt"))
    local tab = wait_for_diff_text("beta")
    assert.is_not_nil(tab, "modified pane should show b.txt")
    local orig = lifecycle.get_buffers(tab)
    h.assert_contains(h.get_buffer_content(orig), "alpha", "original pane shows a.txt")
  end)

  -- ── Directory diff ────────────────────────────────────────────────────────

  it(":CodeDiff dir <d1> <d2> — explorer lists differing files", function()
    repo.write_file("dirA/x.txt", { "A" })
    repo.write_file("dirB/x.txt", { "B" })
    vim.cmd("CodeDiff dir " .. repo.path("dirA") .. " " .. repo.path("dirB"))
    h.assert_contains(explorer_text(), "x.txt")
  end)

  -- ── History ───────────────────────────────────────────────────────────────

  it(":CodeDiff history — shows the commit log", function()
    vim.cmd("CodeDiff history")
    assert.is_true(wait_for_visible("c2"), "history shows commit subjects")
  end)

  it(":CodeDiff history % — history for the current file", function()
    vim.cmd("edit! " .. repo.path("file.txt"))
    vim.cmd("CodeDiff history %")
    assert.is_true(wait_for_visible("c1"), "history shows a commit that touched the file")
  end)

  it(":CodeDiff history --reverse — accepts flags", function()
    vim.cmd("CodeDiff history --reverse")
    assert.is_true(wait_for_visible("c1"))
  end)

  -- ── Layout flags (on a real-file diff) ────────────────────────────────────

  it(":CodeDiff --inline file <a> <b> — inline layout", function()
    vim.cmd("CodeDiff --inline file " .. repo.path("a.txt") .. " " .. repo.path("b.txt"))
    local tab = wait_for_diff_text("beta")
    assert.is_not_nil(tab)
    assert.equals("inline", lifecycle.get_session(tab).layout, "layout is inline")
  end)

  it(":CodeDiff --side-by-side file <a> <b> — side-by-side layout", function()
    vim.cmd("CodeDiff --side-by-side file " .. repo.path("a.txt") .. " " .. repo.path("b.txt"))
    local tab = wait_for_diff_text("beta")
    assert.is_not_nil(tab)
    assert.equals("side-by-side", lifecycle.get_session(tab).layout)
  end)

  -- ── Completion ────────────────────────────────────────────────────────────

  it("completion offers subcommands and git refs", function()
    vim.cmd("lcd " .. repo.dir)
    local cands = commands.complete("", "CodeDiff ")
    for _, name in ipairs({ "file", "dir", "history", "merge", "install" }) do
      assert.is_true(vim.tbl_contains(cands, name), "offers subcommand " .. name)
    end
    assert.is_true(vim.tbl_contains(cands, "HEAD"), "offers HEAD ref")
  end)
end)
