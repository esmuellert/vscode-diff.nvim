-- Test: FFI Integration
-- Validates C <-> Lua boundary and data structure conversion
-- Run with: nvim --headless -c "luafile tests/test_ffi_integration.lua" -c "quit"

vim.opt.rtp:prepend(".")
local diff = require("vscode-diff.diff")

print("=== Test: FFI Integration ===\n")

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

-- Test 1: Basic FFI call works
test("FFI can call compute_diff", function()
  local result = diff.compute_diff({"a"}, {"b"})
  assert(result ~= nil, "Result should not be nil")
end)

-- Test 2: Return structure format
test("Returns correct structure format", function()
  local result = diff.compute_diff({"a"}, {"b"})
  assert(type(result) == "table", "Result should be a table")
  assert(type(result.changes) == "table", "Should have changes array")
  assert(type(result.moves) == "table", "Should have moves array")
  assert(type(result.hit_timeout) == "boolean", "Should have hit_timeout flag")
end)

-- Test 3: Changes array structure
test("Changes have correct nested structure", function()
  local result = diff.compute_diff({"a", "b"}, {"a", "c"})
  assert(#result.changes > 0, "Should have at least one change")
  
  local mapping = result.changes[1]
  assert(type(mapping) == "table", "Mapping should be a table")
  assert(mapping.original, "Should have original range")
  assert(mapping.modified, "Should have modified range")
  assert(type(mapping.inner_changes) == "table", "Should have inner_changes array")
end)

-- Test 4: LineRange structure
test("LineRange has correct fields", function()
  local result = diff.compute_diff({"a"}, {"b"})
  local mapping = result.changes[1]
  
  assert(type(mapping.original.start_line) == "number", "start_line should be number")
  assert(type(mapping.original.end_line) == "number", "end_line should be number")
  assert(mapping.original.start_line >= 1, "start_line should be 1-based")
  assert(mapping.original.end_line >= mapping.original.start_line, "end >= start")
end)

-- Test 5: CharRange structure in inner changes
test("CharRange has correct fields", function()
  local result = diff.compute_diff({"hello"}, {"world"})
  if #result.changes > 0 and #result.changes[1].inner_changes > 0 then
    local inner = result.changes[1].inner_changes[1]
    
    assert(type(inner.original) == "table", "Should have original CharRange")
    assert(type(inner.modified) == "table", "Should have modified CharRange")
    assert(type(inner.original.start_line) == "number")
    assert(type(inner.original.start_col) == "number")
    assert(type(inner.original.end_line) == "number")
    assert(type(inner.original.end_col) == "number")
    assert(inner.original.start_col >= 1, "Column should be 1-based")
  end
end)

-- Test 6: Empty input handling
test("Handles empty arrays", function()
  local result = diff.compute_diff({}, {})
  assert(result ~= nil, "Should handle empty input")
  assert(type(result.changes) == "table")
  assert(#result.changes == 0, "Should have no changes for identical empty inputs")
end)

-- Test 7: Same content (no changes)
test("Handles identical content", function()
  local result = diff.compute_diff({"a", "b", "c"}, {"a", "b", "c"})
  assert(result ~= nil)
  assert(#result.changes == 0, "Should have no changes for identical content")
end)

-- Test 8: Large diff doesn't crash
test("Handles large diffs", function()
  local large_a = {}
  local large_b = {}
  for i = 1, 100 do
    table.insert(large_a, "line " .. i)
    table.insert(large_b, "modified " .. i)
  end
  
  local result = diff.compute_diff(large_a, large_b)
  assert(result ~= nil, "Should handle large diffs")
  assert(#result.changes > 0, "Should detect changes in large diff")
end)

-- Test 9: Memory is freed (basic check - no crash on multiple calls)
test("Multiple calls don't leak memory", function()
  for i = 1, 10 do
    local result = diff.compute_diff(
      {"line1", "line2", "line3"},
      {"line1", "modified", "line3"}
    )
    assert(result ~= nil, "Call " .. i .. " should succeed")
  end
end)

-- Test 10: Version string exists
test("Can get version string", function()
  local version = diff.get_version()
  assert(type(version) == "string", "Version should be a string")
  assert(#version > 0, "Version should not be empty")
  print("    (Version: " .. version .. ")")
end)

-- Summary
print("\n" .. string.rep("=", 50))
if pass_count == test_count then
  print(string.format("✓ All %d FFI integration tests passed", pass_count))
  vim.cmd("cquit 0")
else
  print(string.format("✗ %d/%d tests failed", test_count - pass_count, test_count))
  vim.cmd("cquit 1")
end
