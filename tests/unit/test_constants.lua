-- Unit test: Highlight type constants
-- Run with: nvim --headless -c "luafile tests/unit/test_constants.lua" -c "quit"

print("=== Unit Test: Highlight Constants ===")

vim.opt.rtp:prepend(".")
local diff = require("vscode-diff")

-- Test highlight type constants
assert(diff.HL_LINE_INSERT == 0, "HL_LINE_INSERT value mismatch")
assert(diff.HL_LINE_DELETE == 1, "HL_LINE_DELETE value mismatch")
assert(diff.HL_CHAR_INSERT == 2, "HL_CHAR_INSERT value mismatch")
assert(diff.HL_CHAR_DELETE == 3, "HL_CHAR_DELETE value mismatch")

print("✓ HL_LINE_INSERT = " .. diff.HL_LINE_INSERT)
print("✓ HL_LINE_DELETE = " .. diff.HL_LINE_DELETE)
print("✓ HL_CHAR_INSERT = " .. diff.HL_CHAR_INSERT)
print("✓ HL_CHAR_DELETE = " .. diff.HL_CHAR_DELETE)
print("✓ Test passed")
