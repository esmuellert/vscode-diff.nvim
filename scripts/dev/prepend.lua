-- Preload snippet run by dev.sh (via --cmd luafile) BEFORE the user's
-- init.lua loads.
--
-- Forces THIS worktree's plugin sources to win over any plugin-manager
-- resolution for require("codediff.*"). The rest of the user's editor
-- experience (colorscheme, LSP, keymaps, other plugins) is untouched: only
-- the codediff plugin layer differs per worktree.
--
-- Why the interceptor and not just an rtp/package.path prepend?
--   lazy.nvim (and other managers) reset `runtimepath` inside their setup()
--   call, wiping any prior prepend. Neovim's rtp-based Lua loader runs
--   before the standard `package.path` file loader, so once lazy adds its
--   own resolution to rtp (e.g. via `dev = { path = "~" }` pointing at the
--   primary worktree), require("codediff") resolves there — not here.
--
--   Installing a searcher at `package.loaders[1]` (or `package.searchers`
--   on newer runtimes) short-circuits both loaders: it fires before Neovim
--   scans runtimepath, and it's not sensitive to any later rtp reset.

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

local function load_from_worktree(modname)
  if modname ~= "codediff" and not modname:match("^codediff%.") then
    return nil
  end
  local relpath = modname:gsub("%.", "/")
  local candidates = {
    here .. "/lua/" .. relpath .. ".lua",
    here .. "/lua/" .. relpath .. "/init.lua",
  }
  for _, path in ipairs(candidates) do
    if vim.fn.filereadable(path) == 1 then
      local chunk, err = loadfile(path)
      if chunk then
        return chunk
      end
      return "\n\tcodediff-dev loader: loadfile failed for " .. path .. ": " .. tostring(err)
    end
  end
  return "\n\tcodediff-dev loader: no file for '" .. modname .. "' under " .. here .. "/lua"
end

local searchers = package.loaders or package.searchers
table.insert(searchers, 1, load_from_worktree)

-- Belt-and-braces prepend so the worktree's plugin/* also loads and any
-- non-require lookups (e.g. `runtime! path`) hit the worktree first while
-- rtp is still ours (before the manager's setup runs).
vim.opt.rtp:prepend(here)
package.path = here .. "/lua/?.lua;" .. here .. "/lua/?/init.lua;" .. package.path
