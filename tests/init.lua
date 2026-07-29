-- Test bootstrap for codediff.nvim
--
-- Loads the plugin and installs the in-tree test framework (tests/framework/),
-- which fully replaces plenary.nvim. See tests/framework/init.lua for design
-- notes.

-- Disable auto-installation in tests (library is already built by CI)
vim.env.VSCODE_DIFF_NO_AUTO_INSTALL = "1"

-- Disable ShaDa (fixes Windows permission issues in CI)
vim.opt.shadafile = "NONE"

-- Add current directory to runtimepath
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)

-- Ensure lua/ directory is in package.path for direct requires. Also add the
-- repository root so `require("tests.framework")` resolves to tests/framework/init.lua.
package.path = package.path
  .. ";" .. cwd .. "/lua/?.lua"
  .. ";" .. cwd .. "/lua/?/init.lua"
  .. ";" .. cwd .. "/?.lua"
  .. ";" .. cwd .. "/?/init.lua"

vim.opt.swapfile = false

-- Load plugin files (for integration tests that need commands)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')

-- Setup plugin
require("codediff").setup()

-- Install the in-tree test framework: augments `_G.assert` and installs the
-- `describe`, `it`, `before_each`, `after_each`, `pending` globals.
require("tests.framework").setup()
