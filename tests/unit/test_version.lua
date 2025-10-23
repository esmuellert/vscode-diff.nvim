-- Unit test: Version check
-- Run with: nvim --headless -c "luafile tests/unit/test_version.lua" -c "quit"

print("=== Unit Test: Version ===")

vim.opt.rtp:prepend(".")
local diff = require("vscode-diff")

local version = diff.get_version()
assert(version == "0.1.0", "Version mismatch, expected 0.1.0, got: " .. version)

print("✓ Version: " .. version)
print("✓ Test passed")
