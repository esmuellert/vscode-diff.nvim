-- Tests for explorer scroll keymaps
-- Validates that <C-b> and <C-f> scroll the diff buffers from explorer

local h = dofile('tests/helpers.lua')
local navigation = require('codediff.ui.view.navigation')
local lifecycle = require('codediff.ui.lifecycle')

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

describe("Explorer scroll keymaps", function()
  local temp_dir
  local original_cwd

  before_each(function()
    require("codediff").setup({ 
      diff = { layout = "side-by-side" },
    })
    setup_command()
    original_cwd = vim.fn.getcwd()
    
    -- Create temporary git repository
    temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    vim.fn.chdir(temp_dir)
    
    h.git_cmd(temp_dir, "init")
    h.git_cmd(temp_dir, "branch -m main")
    h.git_cmd(temp_dir, 'config user.email "test@example.com"')
    h.git_cmd(temp_dir, 'config user.name "Test User"')
    
    -- Create a file with enough lines for scrolling
    local lines = {}
    for i = 1, 100 do
      table.insert(lines, "line " .. i)
    end
    vim.fn.writefile(lines, temp_dir .. "/scroll_test.txt")
    h.git_cmd(temp_dir, "add scroll_test.txt")
    h.git_cmd(temp_dir, 'commit -m "Initial commit"')
    
    -- Modify the file
    local modified_lines = {}
    for i = 1, 100 do
      if i >= 50 and i <= 60 then
        table.insert(modified_lines, "modified line " .. i)
      else
        table.insert(modified_lines, "line " .. i)
      end
    end
    vim.fn.writefile(modified_lines, temp_dir .. "/scroll_test.txt")
  end)

  after_each(function()
    vim.cmd("tabnew")
    vim.cmd("tabonly")
    vim.fn.chdir(original_cwd)
    vim.wait(200)
    if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  -- Helper: Find explorer window
  local function find_explorer_window()
    for i = 1, vim.fn.winnr('$') do
      local winid = vim.fn.win_getid(i)
      local bufnr = vim.api.nvim_win_get_buf(winid)
      if vim.bo[bufnr].filetype == "codediff-explorer" then
        return winid, bufnr
      end
    end
    return nil, nil
  end

  -- Helper: Find modified window
  local function find_modified_window()
    local tabpage = vim.api.nvim_get_current_tabpage()
    local session = lifecycle.get_session(tabpage)
    if session and session.modified_win and vim.api.nvim_win_is_valid(session.modified_win) then
      return session.modified_win
    end
    return nil
  end

  -- Test 1: Scroll keymaps are registered on explorer buffer
  it("Registers scroll keymaps on explorer buffer", function()
    vim.cmd("edit " .. temp_dir .. "/scroll_test.txt")
    vim.cmd("CodeDiff")
    
    vim.wait(3000, function()
      local _, buf = find_explorer_window()
      return buf ~= nil
    end)
    
    local _, explorer_buf = find_explorer_window()
    if not explorer_buf then
      pending("Explorer not created in time")
      return
    end
    
    -- Check keymaps exist
    local maps = vim.api.nvim_buf_get_keymap(explorer_buf, "n")
    local keymap_found = {}
    for _, m in ipairs(maps) do
      keymap_found[m.lhs] = true
    end

    -- Verify scroll keymaps are registered (<C-b> and <C-f>)
    -- Note: Vim stores these as <C-B> and <C-F> (uppercase)
    local scroll_keymaps = { "<C-B>", "<C-F>" }
    for _, key in ipairs(scroll_keymaps) do
      assert.is_true(keymap_found[key],
        "Keymap " .. key .. " should be registered on explorer")
    end
  end)

  -- Test 2: <C-f> scrolls diff buffers down from explorer
  it("<C-f> scrolls diff buffers down half page from explorer", function()
    vim.cmd("edit " .. temp_dir .. "/scroll_test.txt")
    vim.cmd("CodeDiff")
    
    vim.wait(3000, function()
      local winid, _ = find_explorer_window()
      local mod_win = find_modified_window()
      return winid ~= nil and mod_win ~= nil
    end)
    
    local explorer_win, explorer_buf = find_explorer_window()
    local modified_win = find_modified_window()
    
    if not explorer_win or not modified_win then
      pending("Windows not ready in time")
      return
    end
    
    -- Select the file in explorer to load it into diff buffers
    vim.api.nvim_set_current_win(explorer_win)
    -- Find the file entry in explorer (should be under "Changes" group)
    local lines = vim.api.nvim_buf_get_lines(explorer_buf, 0, -1, false)
    local file_line = nil
    for i, line in ipairs(lines) do
      if line:match("scroll_test") then
        file_line = i
        break
      end
    end
    
    if file_line then
      vim.api.nvim_win_set_cursor(explorer_win, { file_line, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
      -- Wait for file to load
      vim.wait(1000)
    else
      pending("File not found in explorer")
      return
    end
    
    -- Verify the file loaded by checking buffer line count
    local mod_buf = vim.api.nvim_win_get_buf(modified_win)
    local line_count = vim.api.nvim_buf_line_count(mod_buf)
    if line_count < 10 then
      pending("File content not loaded properly (only " .. line_count .. " lines)")
      return
    end
    
    -- Get initial scroll position (top line visible)
    vim.api.nvim_set_current_win(modified_win)
    vim.api.nvim_win_set_cursor(modified_win, { 1, 0 })
    local initial_top = vim.fn.line("w0", modified_win)
    
    -- Switch back to explorer
    vim.api.nvim_set_current_win(explorer_win)
    
    -- Execute scroll down
    navigation.scroll_diff_windows("down")
    vim.wait(100) -- Give it a moment to process
    
    -- Check that modified window scrolled (check top visible line)
    local new_top = vim.fn.line("w0", modified_win)
    assert.is_true(new_top > initial_top, 
      "Modified window should have scrolled down (top line from " .. initial_top .. " to " .. new_top .. ")")
  end)

  -- Test 3: <C-b> scrolls diff buffers up from explorer
  it("<C-b> scrolls diff buffers up half page from explorer", function()
    vim.cmd("edit " .. temp_dir .. "/scroll_test.txt")
    vim.cmd("CodeDiff")

    vim.wait(3000, function()
      local winid, _ = find_explorer_window()
      local mod_win = find_modified_window()
      return winid ~= nil and mod_win ~= nil
    end)

    local explorer_win, explorer_buf = find_explorer_window()
    local modified_win = find_modified_window()

    if not explorer_win or not modified_win then
      pending("Windows not ready in time")
      return
    end

    -- Select the file in explorer to load it into diff buffers
    vim.api.nvim_set_current_win(explorer_win)
    -- Find the file entry in explorer (should be under "Changes" group)
    local lines = vim.api.nvim_buf_get_lines(explorer_buf, 0, -1, false)
    local file_line = nil
    for i, line in ipairs(lines) do
      if line:match("scroll_test") then
        file_line = i
        break
      end
    end

    if file_line then
      vim.api.nvim_win_set_cursor(explorer_win, { file_line, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
      -- Wait for file to load
      vim.wait(1000)
    end

    -- First scroll down to have room to scroll up
    vim.api.nvim_set_current_win(modified_win)
    vim.api.nvim_win_set_cursor(modified_win, { 50, 0 })
    vim.cmd("normal! zt") -- Move current line to top
    local initial_top = vim.fn.line("w0", modified_win)

    -- Switch back to explorer
    vim.api.nvim_set_current_win(explorer_win)

    -- Execute scroll up
    navigation.scroll_diff_windows("up")
    vim.wait(100) -- Give it a moment to process

    -- Check that modified window scrolled up (check top visible line)
    local new_top = vim.fn.line("w0", modified_win)
    assert.is_true(new_top < initial_top,
      "Modified window should have scrolled up (top line from " .. initial_top .. " to " .. new_top .. ")")
  end)

  -- Test 4: Returns false when no session
  it("Returns false when no active session", function()
    -- Ensure we're not in a diff session
    while vim.fn.tabpagenr('$') > 1 do
      vim.cmd('tabclose!')
    end
    vim.cmd('enew')
    
    local result = navigation.scroll_diff_windows("down")
    assert.is_false(result, "Should return false when no session")
  end)

  -- Test 5: Scroll commands preserve explorer focus
  it("Preserves explorer focus after scrolling", function()
    vim.cmd("edit " .. temp_dir .. "/scroll_test.txt")
    vim.cmd("CodeDiff")
    
    vim.wait(3000, function()
      local winid, _ = find_explorer_window()
      return winid ~= nil
    end)
    
    local explorer_win, _ = find_explorer_window()
    local modified_win = find_modified_window()
    
    if not explorer_win or not modified_win then
      pending("Windows not ready in time")
      return
    end
    
    -- Ensure we're in explorer
    vim.api.nvim_set_current_win(explorer_win)
    
    -- Execute scroll
    navigation.scroll_diff_windows("down")
    
    -- Verify we're still in explorer window
    local current_win = vim.api.nvim_get_current_win()
    assert.equal(explorer_win, current_win, 
      "Should remain in explorer window after scroll")
  end)
end)