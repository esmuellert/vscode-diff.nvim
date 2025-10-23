-- Test filler line rendering
-- Run with: nvim --headless -c "luafile tests/test_filler.lua" -- -v

local verbose = false
for _, arg in ipairs(vim.v.argv) do
  if arg == "-v" or arg == "--verbose" then
    verbose = true
    break
  end
end

print("=== Filler Line Test ===\n")

vim.o.loadplugins = true
vim.opt.rtp:prepend(".")

local diff = require("vscode-diff")

if verbose then
  diff.set_verbose(true)
end

-- Simple case: pure deletion
print("Test 1: Pure Deletion (should have filler on right)")
local lines_a = {"line1", "line2", "line3"}
local lines_b = {"line1", "line3"}
local plan = diff.compute_diff(lines_a, lines_b)

print("\nExpected: Left has 3 lines, Right has 2 real + 1 filler = 3 lines")
print("Actual: Left=" .. plan.left.line_count .. ", Right=" .. plan.right.line_count)

local filler_count = 0
for i, meta in ipairs(plan.right.line_metadata) do
  if meta.is_filler then
    filler_count = filler_count + 1
    print("  Right[" .. i .. "] is a FILLER line")
  end
end
print("Filler lines on right: " .. filler_count)

-- Simple case: pure insertion
print("\n\nTest 2: Pure Insertion (should have filler on left)")
local lines_a2 = {"line1", "line3"}
local lines_b2 = {"line1", "line2", "line3"}
local plan2 = diff.compute_diff(lines_a2, lines_b2)

print("\nExpected: Left has 2 real + 1 filler = 3 lines, Right has 3 lines")
print("Actual: Left=" .. plan2.left.line_count .. ", Right=" .. plan2.right.line_count)

local filler_count2 = 0
for i, meta in ipairs(plan2.left.line_metadata) do
  if meta.is_filler then
    filler_count2 = filler_count2 + 1
    print("  Left[" .. i .. "] is a FILLER line")
  end
end
print("Filler lines on left: " .. filler_count2)

print("\n✓ Filler line test complete")
vim.cmd("quit!")
