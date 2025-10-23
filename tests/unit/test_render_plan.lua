-- Unit test: Basic render plan structure
-- Run with: nvim --headless -c "luafile tests/unit/test_render_plan.lua" -c "quit"

print("=== Unit Test: Render Plan Structure ===\n")

vim.opt.rtp:prepend(".")
local diff = require("vscode-diff")

-- Test 1: Basic structure
print("Test 1: Basic render plan structure")
local lines_a = {"line1", "line2", "line3"}
local lines_b = {"line1", "line2_modified", "line3"}
local plan = diff.compute_diff(lines_a, lines_b)

assert(plan ~= nil, "Plan is nil")
assert(plan.left ~= nil, "Left plan is nil")
assert(plan.right ~= nil, "Right plan is nil")
assert(plan.left.line_count == 3, "Left line count should be 3")
assert(plan.right.line_count == 3, "Right line count should be 3")
assert(plan.left.line_metadata ~= nil, "Left line_metadata is nil")
assert(plan.right.line_metadata ~= nil, "Right line_metadata is nil")
assert(#plan.left.line_metadata == 3, "Left should have 3 metadata entries")
assert(#plan.right.line_metadata == 3, "Right should have 3 metadata entries")

print("✓ Left line count: " .. plan.left.line_count)
print("✓ Right line count: " .. plan.right.line_count)
print("✓ Left metadata count: " .. #plan.left.line_metadata)
print("✓ Right metadata count: " .. #plan.right.line_metadata)

-- Test 2: Metadata structure
print("\nTest 2: Line metadata fields")
local meta = plan.left.line_metadata[1]
assert(meta.line_num ~= nil, "line_num field missing")
assert(meta.type ~= nil, "type field missing")
assert(meta.is_filler ~= nil, "is_filler field missing")
assert(meta.char_highlights ~= nil, "char_highlights field missing")

local char_hl_count = #meta.char_highlights

print("✓ line_num: " .. meta.line_num)
print("✓ type: " .. meta.type)
print("✓ is_filler: " .. tostring(meta.is_filler))
print("✓ char_highlight_count: " .. char_hl_count)

-- Test 3: Character highlight structure (if any)
print("\nTest 3: Character highlight structure")
if char_hl_count > 0 then
  local char_hl = meta.char_highlights[1]
  assert(char_hl.start_col ~= nil, "start_col field missing")
  assert(char_hl.end_col ~= nil, "end_col field missing")
  assert(char_hl.type ~= nil, "type field missing in char highlight")
  print("✓ start_col: " .. char_hl.start_col)
  print("✓ end_col: " .. char_hl.end_col)
  print("✓ type: " .. char_hl.type)
else
  print("✓ No character highlights on this line (expected)")
end

print("\n✓ All render plan structure tests passed")
