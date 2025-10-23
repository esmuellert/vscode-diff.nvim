-- Unit test: Filler line logic
-- Run with: nvim --headless -c "luafile tests/unit/test_filler.lua" -c "quit"

print("=== Unit Test: Filler Lines ===\n")

vim.opt.rtp:prepend(".")
local diff = require("vscode-diff")

-- Test 1: Deletion should create filler on right
print("Test 1: Deletion (filler on right)")
local lines_a = {"line1", "line2", "line3"}
local lines_b = {"line1", "line3"}
local plan = diff.compute_diff(lines_a, lines_b)

assert(plan.left.line_count == 3, "Left should have 3 lines")
assert(plan.right.line_count == 3, "Right should have 3 lines (with filler)")

local filler_count = 0
for _, meta in ipairs(plan.right.line_metadata) do
  if meta.is_filler then
    filler_count = filler_count + 1
  end
end

assert(filler_count == 1, "Right should have 1 filler line, got: " .. filler_count)
print("✓ Right has " .. filler_count .. " filler line")

-- Test 2: Insertion should create filler on left
print("\nTest 2: Insertion (filler on left)")
local lines_a2 = {"line1", "line3"}
local lines_b2 = {"line1", "line2", "line3"}
local plan2 = diff.compute_diff(lines_a2, lines_b2)

assert(plan2.left.line_count == 3, "Left should have 3 lines (with filler)")
assert(plan2.right.line_count == 3, "Right should have 3 lines")

local filler_count2 = 0
for _, meta in ipairs(plan2.left.line_metadata) do
  if meta.is_filler then
    filler_count2 = filler_count2 + 1
  end
end

assert(filler_count2 == 1, "Left should have 1 filler line, got: " .. filler_count2)
print("✓ Left has " .. filler_count2 .. " filler line")

print("\n✓ All filler tests passed")
