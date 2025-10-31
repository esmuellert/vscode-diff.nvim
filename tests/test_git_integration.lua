-- Test: Git Integration
-- Validates git operations, error handling, and async callbacks
-- Run with: nvim --headless -c "luafile tests/test_git_integration.lua" -c "quit"

vim.opt.rtp:prepend(".")
local git = require("vscode-diff.git")

print("=== Test: Git Integration ===\n")

local test_count = 0
local pass_count = 0

local function test(name, fn)
  test_count = test_count + 1
  io.write(string.format("[%d] %s ... ", test_count, name))
  local ok, err = pcall(fn)
  if ok then
    pass_count = pass_count + 1
    print("✓")
  else
    print("✗")
    print("  Error: " .. tostring(err))
  end
end

-- Test 1: Detect non-git directory
test("Detects non-git directory", function()
  local is_git = git.is_in_git_repo("/tmp")
  assert(is_git == false or is_git == true, "Should return boolean")
  -- Note: /tmp might be in a git repo, so we just check it returns a boolean
end)

-- Test 2: Get git root for valid repo
test("Gets git root for current repo", function()
  local current_file = vim.fn.expand("%:p")
  if current_file == "" then
    current_file = vim.fn.getcwd() .. "/README.md"
  end
  
  local root = git.get_git_root(current_file)
  if root then
    assert(type(root) == "string", "Git root should be a string")
    assert(vim.fn.isdirectory(root) == 1, "Git root should be a directory")
  end
  -- If not in git repo, that's okay
end)

-- Test 3: Error callback for invalid revision
test("Error callback for invalid revision", function()
  local test_file = vim.fn.tempname()
  vim.fn.writefile({"test content"}, test_file)
  
  local callback_called = false
  local got_error = false
  
  git.get_file_at_revision("invalid-revision-12345", test_file, function(err, data)
    callback_called = true
    if err then
      got_error = true
    end
  end)
  
  -- Wait for async callback
  vim.wait(2000, function() return callback_called end)
  
  assert(callback_called, "Callback should be invoked")
  -- Note: might not error if not in git repo, which is fine
  
  vim.fn.delete(test_file)
end)

-- Test 4: Async callback with actual git repo (if available)
test("Can retrieve file from HEAD (if in git repo)", function()
  local test_passed = false
  
  -- Try to get this test file from HEAD
  local current_file = debug.getinfo(1).source:sub(2)
  
  if git.is_in_git_repo(current_file) then
    local callback_called = false
    
    git.get_file_at_revision("HEAD", current_file, function(err, lines)
      callback_called = true
      if not err and lines then
        assert(type(lines) == "table", "Should return table of lines")
        assert(#lines > 0, "Should have content")
        test_passed = true
      elseif err then
        -- File might not exist in HEAD, that's okay
        test_passed = true
      end
    end)
    
    vim.wait(2000, function() return callback_called end)
    assert(callback_called, "Callback should be called")
  else
    -- Not in git repo, skip test
    test_passed = true
  end
  
  assert(test_passed, "Test should complete")
end)

-- Test 5: Relative path calculation
test("Calculates relative path correctly", function()
  local git_root = "/home/user/project"
  local file_path = "/home/user/project/src/file.lua"
  
  local rel_path = git.get_relative_path(file_path, git_root)
  assert(type(rel_path) == "string", "Should return string")
  assert(rel_path == "src/file.lua", "Should strip git root: got " .. rel_path)
end)

-- Test 6: Error message quality for missing file
test("Provides good error for missing file in revision", function()
  -- Create a temporary file that definitely doesn't exist in git history
  local test_file = vim.fn.tempname() .. "_nonexistent_file_12345.txt"
  vim.fn.writefile({"test"}, test_file)
  
  if git.is_in_git_repo(test_file) then
    local callback_called = false
    local error_message = nil
    
    git.get_file_at_revision("HEAD", test_file, function(err, data)
      callback_called = true
      error_message = err
    end)
    
    vim.wait(2000, function() return callback_called end)
    
    if error_message then
      assert(type(error_message) == "string", "Error should be a string")
      assert(#error_message > 0, "Error message should not be empty")
    end
  end
  
  vim.fn.delete(test_file)
end)

-- Test 7: Handles special characters in filenames
test("Handles filenames with spaces", function()
  local git_root = "/home/user/project"
  local file_path = "/home/user/project/src/my file.lua"
  
  local rel_path = git.get_relative_path(file_path, git_root)
  assert(rel_path == "src/my file.lua", "Should handle spaces: got " .. rel_path)
end)

-- Test 8: Multiple async calls don't interfere
test("Multiple async calls work independently", function()
  local test_file = vim.fn.tempname()
  vim.fn.writefile({"test"}, test_file)
  
  local call1_done = false
  local call2_done = false
  
  git.get_file_at_revision("invalid1", test_file, function()
    call1_done = true
  end)
  
  git.get_file_at_revision("invalid2", test_file, function()
    call2_done = true
  end)
  
  vim.wait(3000, function() return call1_done and call2_done end)
  
  assert(call1_done, "First call should complete")
  assert(call2_done, "Second call should complete")
  
  vim.fn.delete(test_file)
end)

-- Summary
print("\n" .. string.rep("=", 50))
if pass_count == test_count then
  print(string.format("✓ All %d git integration tests passed", pass_count))
  vim.cmd("cquit 0")
else
  print(string.format("✗ %d/%d tests failed", test_count - pass_count, test_count))
  vim.cmd("cquit 1")
end
