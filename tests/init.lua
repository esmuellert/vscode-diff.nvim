-- Test init file for plenary tests
-- This loads the plugin and plenary.nvim

-- Disable auto-installation in tests (library is already built by CI)
vim.env.VSCODE_DIFF_NO_AUTO_INSTALL = "1"

-- Disable ShaDa (fixes Windows permission issues in CI)
vim.opt.shadafile = "NONE"

-- Add current directory to runtimepath
local cwd = vim.fn.getcwd()
vim.opt.rtp:prepend(cwd)

-- Ensure lua/ directory is in package.path for direct requires
package.path = package.path .. ";" .. cwd .. "/lua/?.lua;" .. cwd .. "/lua/?/init.lua"

vim.opt.swapfile = false

-- Setup plenary.nvim in Neovim's data directory (proper location)
local plenary_dir = vim.fn.stdpath("data") .. "/plenary.nvim"
if vim.fn.isdirectory(plenary_dir) == 0 then
  -- Clone plenary if not found
  print("Installing plenary.nvim for tests...")
  vim.fn.system({
    "git",
    "clone",
    "--depth=1",
    "https://github.com/nvim-lua/plenary.nvim",
    plenary_dir,
  })
end
vim.opt.rtp:prepend(plenary_dir)

-- Load this project's plugin files only (for integration tests that need commands).
-- Avoid `runtime! plugin/*.lua`, which also sources unrelated user plugins on
-- the runtimepath and can make tests fail depending on the local Neovim setup.
for _, plugin_file in ipairs(vim.fn.glob(cwd .. "/plugin/*.lua", false, true)) do
  vim.cmd("source " .. vim.fn.fnameescape(plugin_file))
end

-- Setup plugin
require("codediff").setup()
