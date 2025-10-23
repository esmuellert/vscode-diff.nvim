-- Unit test: Character-level diff
-- Run with: nvim --headless -c "luafile tests/unit/test_char_diff.lua" -c "quit"

print("=== Unit Test: Character-level Diff ===\n")

vim.opt.rtp:prepend(".")
local diff = require("vscode-diff")

-- Test 1: Single character change
print("Test 1: Single character change")
local lines_a = {"hello"}
local lines_b = {"hallo"}
local plan = diff.compute_diff(lines_a, lines_b)

assert(plan.left.line_metadata[1].char_highlights ~= nil, "Left char highlights missing")
assert(plan.right.line_metadata[1].char_highlights ~= nil, "Right char highlights missing")
assert(#plan.left.line_metadata[1].char_highlights > 0, "Left should have char highlights")
assert(#plan.right.line_metadata[1].char_highlights > 0, "Right should have char highlights")

print("✓ Left char highlights: " .. #plan.left.line_metadata[1].char_highlights)
print("✓ Right char highlights: " .. #plan.right.line_metadata[1].char_highlights)

-- Test 2: Word replacement
print("\nTest 2: Word replacement")
local lines_a2 = {"hello world"}
local lines_b2 = {"hello there"}
local plan2 = diff.compute_diff(lines_a2, lines_b2)

assert(#plan2.left.line_metadata[1].char_highlights > 0, "Left should have char highlights")
assert(#plan2.right.line_metadata[1].char_highlights > 0, "Right should have char highlights")

print("✓ Left char highlights: " .. #plan2.left.line_metadata[1].char_highlights)
print("✓ Right char highlights: " .. #plan2.right.line_metadata[1].char_highlights)

-- Test 3: No character changes (line-level only)
print("\nTest 3: Complete line change")
local lines_a3 = {"completely different"}
local lines_b3 = {"totally new line"}
local plan3 = diff.compute_diff(lines_a3, lines_b3)

-- Should have character highlights showing the full difference
assert(plan3.left.line_metadata[1].char_highlights ~= nil, "Left char highlights missing")
assert(plan3.right.line_metadata[1].char_highlights ~= nil, "Right char highlights missing")

print("✓ Left char highlights: " .. #plan3.left.line_metadata[1].char_highlights)
print("✓ Right char highlights: " .. #plan3.right.line_metadata[1].char_highlights)

print("\n✓ All character diff tests passed")
