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

-- Opt out of Neovim's file-watcher backing for 'autoread' (its documented
-- `g:loaded_autoread` guard, see $VIMRUNTIME/plugin/autoread.lua). The option
-- itself stays on, so `:checktime` still reloads buffers silently; only the
-- `uv_fs_event` handle that Neovim attaches to every loaded file buffer goes
-- away.
--
-- Specs open files inside throwaway git repos and then delete those repos, which
-- leaves watchers pointing at paths that no longer exist. On Linux that only
-- prints `E211: File ... no longer available`, but on Windows the fs_event
-- callback is handed EPERM repeatedly and Neovim's own callback asserts on it, so
-- the error is re-raised forever: stderr fills with tracebacks and the spec's
-- event loop never makes progress until the per-spec timeout kills it.
--
-- Must be set before the `runtime! plugin/*.lua` below, which is what sources
-- Neovim's runtime plugins despite `--noplugin`.
vim.g.loaded_autoread = 1

-- Load plugin files (for integration tests that need commands)
vim.cmd('runtime! plugin/*.lua plugin/*.vim')

-- Setup plugin
require("codediff").setup()

-- Install the in-tree test framework: augments `_G.assert` and installs the
-- `describe`, `it`, `before_each`, `after_each`, `pending` globals.
require("tests.framework").setup()
