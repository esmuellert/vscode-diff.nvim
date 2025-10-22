-- E2E test script
-- Run with: nvim --headless -c "luafile tests/e2e_test.lua"

print("=== E2E Test ===")

vim.o.loadplugins = true
vim.opt.rtp:prepend(".")

local diff = require("vscode-diff")
local render = require("vscode-diff.render")

-- Test 1: Version
print("\nTest 1: Version")
local version = diff.get_version()
print("Version: " .. version)
assert(version == "0.1.0", "Version mismatch")
print("✓ Version test passed")

-- Test 2: Diff computation
print("\nTest 2: Diff computation")
local lines_a = { "line1", "line2", "line3" }
local lines_b = { "line1", "line2_modified", "line3" }

local plan = diff.compute_diff(lines_a, lines_b)
assert(plan ~= nil, "Plan is nil")
assert(#plan.left.line_metadata == 3, "Left metadata count mismatch: got " .. #plan.left.line_metadata)
assert(#plan.right.line_metadata == 3, "Right metadata count mismatch: got " .. #plan.right.line_metadata)
print("✓ Diff computation test passed")

-- Test 3: Highlight setup
print("\nTest 3: Highlight setup")
render.setup_highlights()
-- Check that highlight groups are defined
local hl_line_insert = vim.api.nvim_get_hl(0, {name = "VscodeDiffLineInsert"})
local hl_char_insert = vim.api.nvim_get_hl(0, {name = "VscodeDiffCharInsert"})
assert(hl_line_insert ~= nil, "VscodeDiffLineInsert not defined")
assert(hl_char_insert ~= nil, "VscodeDiffCharInsert not defined")
print("✓ Highlight setup test passed")

-- Test 4: Buffer creation and rendering
print("\nTest 4: Buffer rendering")
local buffers = render.render_diff(lines_a, lines_b, plan)
assert(buffers.buf_left ~= nil, "Left buffer not created")
assert(buffers.buf_right ~= nil, "Right buffer not created")
assert(buffers.win_left ~= nil, "Left window not created")
assert(buffers.win_right ~= nil, "Right window not created")
print("✓ Buffer rendering test passed")

-- Test 5: File loading
print("\nTest 5: File loading")
local file_a = "tests/fixtures/file_a.txt"
local file_b = "tests/fixtures/file_b.txt"

-- Check files exist
assert(vim.fn.filereadable(file_a) == 1, "File A not found")
assert(vim.fn.filereadable(file_b) == 1, "File B not found")

local flines_a = vim.fn.readfile(file_a)
local flines_b = vim.fn.readfile(file_b)

assert(#flines_a > 0, "File A is empty")
assert(#flines_b > 0, "File B is empty")

local fplan = diff.compute_diff(flines_a, flines_b)
assert(fplan ~= nil, "File diff plan is nil")
print("✓ File loading test passed")

print("\n✓ All E2E tests passed!")
print("Quitting...")
vim.cmd("qa!")
