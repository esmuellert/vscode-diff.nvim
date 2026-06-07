-- Test: inline diff mode with explorer integration
-- Verifies that layout="inline" creates a single diff window (not two),
-- file switches re-render extmarks, and untracked files display correctly.

local view = require("codediff.ui.view")
local inline_view = require("codediff.ui.view.inline_view")
local diff = require("codediff.core.diff")
local highlights = require("codediff.ui.highlights")
local lifecycle = require("codediff.ui.lifecycle")
local inline = require("codediff.ui.inline")

local ns_inline = vim.api.nvim_create_namespace("codediff-inline")

-- Helper to get OS-appropriate temp path
local function get_temp_path(filename)
  local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
  local temp_dir = is_windows and (vim.fn.getenv("TEMP") or "C:\\Windows\\Temp") or "/tmp"
  local sep = is_windows and "\\" or "/"
  return temp_dir .. sep .. filename
end

-- Helper to get OS-appropriate temp dir
local function get_temp_dir()
  local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
  return is_windows and (vim.fn.getenv("TEMP") or "C:\\Windows\\Temp") or "/tmp"
end

-- Helper: count extmarks in the inline namespace on a buffer
local function count_inline_extmarks(bufnr)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_inline, 0, -1, {})
  return #marks
end

-- Helper: create an inline explorer placeholder session (no file selected yet)
local function create_explorer_placeholder(temp_dir)
  local status_result = { unstaged = {}, staged = {}, conflicts = {} }
  local session_config = {
    mode = "explorer",
    git_root = temp_dir,
    original_path = "",
    modified_path = "",
    explorer_data = { status_result = status_result },
  }
  local result = view.create(session_config)
  local tabpage = vim.api.nvim_get_current_tabpage()
  return result, tabpage
end

-- Helper: create an inline view with actual diff content (non-explorer standalone)
local function create_inline_diff_view(original_lines, modified_lines, left_path, right_path)
  local session_config = {
    mode = "standalone",
    git_root = nil,
    original_path = left_path,
    modified_path = right_path,
    original_revision = nil,
    modified_revision = nil,
  }
  local result = view.create(session_config)
  local tabpage = vim.api.nvim_get_current_tabpage()
  return result, tabpage
end

describe("Inline diff with explorer", function()
  before_each(function()
    require("codediff").setup({ diff = { layout = "inline" } })
    highlights.setup()
  end)

  after_each(function()
    -- Close all extra tabs
    while vim.fn.tabpagenr("$") > 1 do
      vim.cmd("tabclose!")
    end
    -- Reset config to default side-by-side
    require("codediff").setup({ diff = { layout = "side-by-side" } })
  end)

  -- =========================================================================
  -- Test 1: Explorer placeholder creates a single window (not two)
  -- =========================================================================
  it("Explorer placeholder creates single window with inline layout", function()
    local temp_dir = get_temp_dir()
    local initial_tabs = vim.fn.tabpagenr("$")

    local result, tabpage = create_explorer_placeholder(temp_dir)

    -- Should create a new tab
    assert.equal(initial_tabs + 1, vim.fn.tabpagenr("$"), "Should create a new tab")

    -- The session should exist and be marked as inline
    local session = lifecycle.get_session(tabpage)
    assert.is_not_nil(session, "Session should exist")
    assert.equal("inline", session.layout, "Session layout should be 'inline'")

    -- Count non-explorer windows: in inline mode we expect exactly 1 diff window
    -- (explorer sidebar may or may not exist depending on nui availability)
    local wins = vim.api.nvim_tabpage_list_wins(tabpage)
    local diff_wins = {}
    for _, win in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      -- Explorer has filetype "codediff-explorer"; diff window does not
      if ft ~= "codediff-explorer" and ft ~= "codediff-history" then
        table.insert(diff_wins, win)
      end
    end

    assert.equal(1, #diff_wins, "Inline layout should have exactly 1 diff window (not 2)")

    -- Both original_win and modified_win should point to the same window
    assert.equal(session.original_win, session.modified_win,
      "In inline mode, original_win and modified_win should be the same window")

    -- Result should contain buffers
    assert.is_not_nil(result, "create() should return a result")
    assert.is_not_nil(result.modified_buf, "Result should have modified_buf")
    assert.is_not_nil(result.original_buf, "Result should have original_buf")
  end)

  -- =========================================================================
  -- Test 2: File switch re-renders (old extmarks cleared, new extmarks present)
  -- =========================================================================
  it("File switch clears old extmarks and renders new ones", function()
    -- Create initial diff files
    local original_a = { "line 1", "line 2", "line 3" }
    local modified_a = { "line 1", "CHANGED", "line 3" }
    local left_a = get_temp_path("inline_switch_left_a.txt")
    local right_a = get_temp_path("inline_switch_right_a.txt")
    vim.fn.writefile(original_a, left_a)
    vim.fn.writefile(modified_a, right_a)

    local result, tabpage = create_inline_diff_view(original_a, modified_a, left_a, right_a)

    -- Wait for async render
    vim.cmd("redraw")
    vim.wait(300, function()
      local session = lifecycle.get_session(tabpage)
      return session and session.stored_diff_result ~= nil
    end, 20)

    -- Verify extmarks exist on the modified buffer
    local session = lifecycle.get_session(tabpage)
    assert.is_not_nil(session, "Session should exist after create")

    local mod_buf_a = session.modified_bufnr
    local marks_before = count_inline_extmarks(mod_buf_a)
    assert.is_true(marks_before > 0, "Should have inline extmarks after initial render")

    -- Now switch to different files via view.update()
    local original_b = { "alpha", "beta" }
    local modified_b = { "alpha", "gamma", "delta" }
    local left_b = get_temp_path("inline_switch_left_b.txt")
    local right_b = get_temp_path("inline_switch_right_b.txt")
    vim.fn.writefile(original_b, left_b)
    vim.fn.writefile(modified_b, right_b)

    local update_config = {
      mode = "standalone",
      git_root = nil,
      original_path = left_b,
      modified_path = right_b,
      original_revision = nil,
      modified_revision = nil,
    }

    view.update(tabpage, update_config, false)

    -- Wait for async re-render
    vim.cmd("redraw")
    vim.wait(300, function()
      local s = lifecycle.get_session(tabpage)
      if not s then return false end
      -- Check that buffers have changed or diff result updated
      return s.modified_bufnr ~= mod_buf_a or s.modified_path == right_b
    end, 20)

    -- Old buffer extmarks should be cleared
    if vim.api.nvim_buf_is_valid(mod_buf_a) then
      local old_marks = count_inline_extmarks(mod_buf_a)
      assert.equal(0, old_marks, "Old buffer should have extmarks cleared after switch")
    end

    -- New buffer should have extmarks
    local session_after = lifecycle.get_session(tabpage)
    assert.is_not_nil(session_after, "Session should still exist after update")
    local mod_buf_b = session_after.modified_bufnr
    if vim.api.nvim_buf_is_valid(mod_buf_b) then
      vim.wait(200, function()
        return count_inline_extmarks(mod_buf_b) > 0
      end, 20)
      local new_marks = count_inline_extmarks(mod_buf_b)
      assert.is_true(new_marks > 0, "New buffer should have inline extmarks after switch")
    end

    -- Cleanup temp files
    vim.fn.delete(left_a)
    vim.fn.delete(right_a)
    vim.fn.delete(left_b)
    vim.fn.delete(right_b)
  end)

  -- =========================================================================
  -- Test 3: Untracked file shows without diff extmarks
  -- =========================================================================
  it("Untracked file via show_single_file has no inline extmarks", function()
    local temp_dir = get_temp_dir()

    -- First create an explorer placeholder to establish a session
    local result, tabpage = create_explorer_placeholder(temp_dir)
    assert.is_not_nil(result, "Placeholder should be created")

    -- Create a temp file to simulate an untracked file
    local untracked_path = get_temp_path("inline_untracked.txt")
    vim.fn.writefile({ "untracked line 1", "untracked line 2", "untracked line 3" }, untracked_path)

    -- Show single file (like selecting an untracked file in explorer)
    inline_view.show_single_file(tabpage, untracked_path)

    -- Wait for buffer to load
    vim.cmd("redraw")
    vim.wait(200, function()
      local session = lifecycle.get_session(tabpage)
      return session and session.modified_path == untracked_path
    end, 20)

    -- Verify: session updated to point at the file
    local session = lifecycle.get_session(tabpage)
    assert.is_not_nil(session, "Session should exist")
    assert.equal(untracked_path, session.modified_path, "modified_path should be the untracked file")

    -- Verify: the buffer should contain the file content
    local mod_buf = session.modified_bufnr
    assert.is_true(vim.api.nvim_buf_is_valid(mod_buf), "Modified buffer should be valid")
    local lines = vim.api.nvim_buf_get_lines(mod_buf, 0, -1, false)
    assert.equal(3, #lines, "Buffer should have 3 lines of content")
    assert.equal("untracked line 1", lines[1], "First line should match file content")

    -- Verify: NO inline diff extmarks (no diff for untracked files)
    local marks = count_inline_extmarks(mod_buf)
    assert.equal(0, marks, "Untracked file should have no inline diff extmarks")

    -- Verify: diff result should be empty
    assert.is_not_nil(session.stored_diff_result, "stored_diff_result should exist")
    if session.stored_diff_result.changes then
      assert.equal(0, #session.stored_diff_result.changes,
        "Untracked file should have no diff changes")
    end

    -- Cleanup
    vim.fn.delete(untracked_path)
  end)

  -- =========================================================================
  -- Test 4: Back to diff after single file restores inline extmarks
  -- =========================================================================
  it("Returning to diff after show_single_file restores inline extmarks", function()
    local temp_dir = get_temp_dir()

    -- Create placeholder session
    local result, tabpage = create_explorer_placeholder(temp_dir)
    assert.is_not_nil(result, "Placeholder should be created")

    -- Show single file first (simulates selecting an untracked file)
    local untracked_path = get_temp_path("inline_back_untracked.txt")
    vim.fn.writefile({ "some content" }, untracked_path)
    inline_view.show_single_file(tabpage, untracked_path)

    vim.cmd("redraw")
    vim.wait(200, function()
      local s = lifecycle.get_session(tabpage)
      return s and s.modified_path == untracked_path
    end, 20)

    -- Verify no extmarks after single file
    local session_single = lifecycle.get_session(tabpage)
    local single_buf = session_single.modified_bufnr
    assert.equal(0, count_inline_extmarks(single_buf),
      "Single file should have no inline extmarks")

    -- Now switch to a diff (simulates selecting a modified file in explorer)
    local orig_lines = { "hello", "world" }
    local mod_lines = { "hello", "earth" }
    local orig_path = get_temp_path("inline_back_orig.txt")
    local mod_path = get_temp_path("inline_back_mod.txt")
    vim.fn.writefile(orig_lines, orig_path)
    vim.fn.writefile(mod_lines, mod_path)

    local update_config = {
      mode = "explorer",
      git_root = temp_dir,
      original_path = orig_path,
      modified_path = mod_path,
      original_revision = nil,
      modified_revision = nil,
    }

    view.update(tabpage, update_config, false)

    -- Wait for async diff render
    vim.cmd("redraw")
    vim.wait(500, function()
      local s = lifecycle.get_session(tabpage)
      if not s then return false end
      if not vim.api.nvim_buf_is_valid(s.modified_bufnr) then return false end
      return count_inline_extmarks(s.modified_bufnr) > 0
    end, 20)

    -- Verify inline extmarks are now present
    local session_diff = lifecycle.get_session(tabpage)
    assert.is_not_nil(session_diff, "Session should exist after update")
    local diff_buf = session_diff.modified_bufnr
    assert.is_true(vim.api.nvim_buf_is_valid(diff_buf), "Diff buffer should be valid")

    local marks = count_inline_extmarks(diff_buf)
    assert.is_true(marks > 0,
      "Should have inline extmarks after switching back to diff (got " .. marks .. ")")

    -- Cleanup
    vim.fn.delete(untracked_path)
    vim.fn.delete(orig_path)
    vim.fn.delete(mod_path)
  end)

  -- =========================================================================
  -- Test 5: Repeated show_single_file for the same real file keeps bufnr stable
  -- =========================================================================
  -- Regression test for #401 (real-file path). bufadd-based loading guarantees
  -- the same bufnr for the same file path, so the window swap is a no-op and
  -- the cursor is preserved across explorer refresh ticks.
  it("Repeated show_single_file with same real file keeps bufnr stable", function()
    local temp_dir = get_temp_dir()
    local _, tabpage = create_explorer_placeholder(temp_dir)

    local file_path = get_temp_path("inline_dedup_real.txt")
    vim.fn.writefile({ "line one", "line two", "line three" }, file_path)

    inline_view.show_single_file(tabpage, file_path)
    vim.cmd("redraw")
    vim.wait(200, function()
      local s = lifecycle.get_session(tabpage)
      return s and s.modified_path == file_path
    end, 20)

    local session_first = lifecycle.get_session(tabpage)
    assert.is_not_nil(session_first, "Session should exist after first call")
    local bufnr_first = session_first.modified_bufnr
    assert.is_true(vim.api.nvim_buf_is_valid(bufnr_first), "First bufnr should be valid")

    -- Place the cursor on line 3 to detect any reset
    local mod_win = session_first.modified_win
    if mod_win and vim.api.nvim_win_is_valid(mod_win) then
      pcall(vim.api.nvim_win_set_cursor, mod_win, { 3, 0 })
    end

    for _ = 1, 4 do
      inline_view.show_single_file(tabpage, file_path)
    end

    local session_after = lifecycle.get_session(tabpage)
    assert.equal(bufnr_first, session_after.modified_bufnr,
      "Repeated show_single_file should not change modified_bufnr (got "
        .. tostring(session_after.modified_bufnr) .. ", expected " .. tostring(bufnr_first) .. ")")

    vim.fn.delete(file_path)
  end)

  -- =========================================================================
  -- Test 6: Repeated show_single_file for staged virtual file keeps bufnr
  -- stable (the original #401 scenario)
  -- =========================================================================
  -- Previously the virtual-file branch did vim.api.nvim_create_buf(false, true)
  -- on every call, so each refresh tick swapped a fresh scratch buffer into
  -- the modified window and reset the cursor. The fix replaces that with
  -- bufadd(virtual_file.create_url(...)), which returns a stable bufnr keyed
  -- by (git_root, revision, path) — same pattern as side_by_side.lua.
  it("Repeated show_single_file for staged virtual file keeps bufnr stable (#401)", function()
    if vim.fn.executable("git") ~= 1 then
      pending("git not available")
      return
    end

    -- Create a real git repo with a staged newly-added file
    local repo = vim.fn.tempname()
    vim.fn.mkdir(repo, "p")
    local function git(args)
      local out = vim.fn.system({ "git", "-C", repo, unpack(args) })
      assert(vim.v.shell_error == 0, "git " .. table.concat(args, " ") .. " failed: " .. out)
    end
    git({ "init", "-q" })
    git({ "config", "user.email", "t@t" })
    git({ "config", "user.name", "t" })

    local rel = "newfile.txt"
    vim.fn.writefile({ "alpha", "beta", "gamma", "delta" }, repo .. "/" .. rel)
    git({ "add", rel })

    local _, tabpage = create_explorer_placeholder(repo)

    inline_view.show_single_file(tabpage, rel, {
      revision = ":0",
      git_root = repo,
      rel_path = rel,
      side = "modified",
    })

    vim.cmd("redraw")
    vim.wait(500, function()
      local s = lifecycle.get_session(tabpage)
      return s and s.modified_revision == ":0" and s.modified_path == rel
    end, 20)

    local session_first = lifecycle.get_session(tabpage)
    assert.is_not_nil(session_first, "Session should exist after first call")
    local bufnr_first = session_first.modified_bufnr
    assert.is_true(vim.api.nvim_buf_is_valid(bufnr_first), "First bufnr should be valid")
    assert.equal(":0", session_first.modified_revision, "modified_revision should be :0")

    -- Repeated calls — would churn bufnr without #401 fix
    for _ = 1, 5 do
      inline_view.show_single_file(tabpage, rel, {
        revision = ":0",
        git_root = repo,
        rel_path = rel,
        side = "modified",
      })
    end

    local session_after = lifecycle.get_session(tabpage)
    assert.equal(bufnr_first, session_after.modified_bufnr,
      "Staged virtual file: bufnr must stay stable across repeated show_single_file calls (got "
        .. tostring(session_after.modified_bufnr) .. ", expected " .. tostring(bufnr_first) .. ")")

    vim.fn.delete(repo, "rf")
  end)
end)
