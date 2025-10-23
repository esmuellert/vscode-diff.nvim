-- Unit test: Version check
-- Run with: nvim --headless -c "luafile tests/unit/test_version.lua" -c "quit"

print("=== Unit Test: Version ===")

vim.opt.rtp:prepend(".")
local diff = require("vscode-diff")

local version = diff.get_version()
assert(version == "0.2.0-stub", "Version mismatch, expected 0.2.0-stub, got: " .. version)

print("✓ Version: " .. version)
print("✓ Test passed")
