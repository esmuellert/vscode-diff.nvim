-- Preload snippet run by dev.sh (via --cmd luafile) BEFORE the user's
-- init.lua loads.
--
-- Prepends THIS worktree's plugin sources to runtimepath and package.path so
-- any require("codediff.*") — from the user's config, from another plugin,
-- or from a lazy-loaded spec — resolves to this worktree's Lua rather than
-- whatever copy their plugin manager installed. The rest of the user's
-- editor experience (colorscheme, LSP, keymaps, other plugins) is
-- untouched: only the codediff plugin layer differs per worktree.

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

vim.opt.rtp:prepend(here)
package.path = here .. "/lua/?.lua;" .. here .. "/lua/?/init.lua;" .. package.path
