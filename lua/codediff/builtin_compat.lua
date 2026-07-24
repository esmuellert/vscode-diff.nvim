-- Minimal compatibility layer with Neovim's built-in diff (vimdiff).
--
-- codediff already provides its own engine, view, keymaps and git
-- integration. This module only covers the built-in diff *entry points* with
-- thin proxy commands and autocmds — no engine changes. Interface differences
-- from built-in diff are accepted by design.
--
-- Provided (trivial, proxy/autocmd only):
--   * :Diffsplit {file}  -> open a codediff of the current buffer vs {file}
--   * :Diffoff           -> close the codediff view in the current tab
--   * `nvim -d f1 f2`    -> open codediff at startup instead of built-in diff
--   * 'diffopt' iwhite*  -> sync onto codediff ignore_trim_whitespace (opt-in)
--
-- Deliberately NOT provided here (they need real work, see commit message):
--   * :Diffthis on an unsaved buffer, :Diffpatch, :Diffupdate, icase/algorithm

local M = {}

local config = require("codediff.config")

local setup_done = false

-- ============================================================================
-- 'diffopt' sync (opt-in): map iwhite/iwhiteeol -> ignore_trim_whitespace.
-- Read lazily from the current 'diffopt' value so it works regardless of
-- whether OptionSet autocmds fire (they do not in headless contexts).
-- ============================================================================
function M.apply_diffopt()
  if not config.options.builtin_compat.sync_diffopt then
    return
  end
  local dip = vim.o.diffopt or ""
  config.options.diff.ignore_trim_whitespace = dip:find("iwhite", 1, true) ~= nil
end

local function on_option_diffopt()
  M.apply_diffopt()
end

-- ============================================================================
-- :Diffsplit {file}
-- Compare the current buffer with another file via codediff.
-- ============================================================================
local function cmd_diffsplit(opts)
  if not config.options.builtin_compat.commands then
    vim.notify("codediff builtin compatibility is disabled", vim.log.levels.WARN)
    return
  end

  local target = vim.fn.expand(opts.fargs[1])
  if target == "" then
    vim.notify("Usage: :Diffsplit {file}", vim.log.levels.ERROR)
    return
  end

  local current = vim.api.nvim_buf_get_name(0)
  if current == "" or vim.bo[0].buftype ~= "" then
    vim.notify(":Diffsplit needs a file buffer to diff from", vim.log.levels.ERROR)
    return
  end
  if vim.fn.filereadable(target) ~= 1 then
    vim.notify("File not found: " .. target, vim.log.levels.ERROR)
    return
  end

  -- Delegate to the existing :CodeDiff file handler (lazy require: heavy).
  M.apply_diffopt()
  local commands = require("codediff.commands")
  commands.vscode_diff({ fargs = { "file", current, target } })
end

-- ============================================================================
-- :Diffoff
-- Close the codediff view in the current tab (reuse lifecycle.close).
-- ============================================================================
local function cmd_diffoff()
  local lifecycle = require("codediff.ui.lifecycle")
  local tab = vim.api.nvim_get_current_tabpage()
  if not lifecycle.get_session(tab) then
    vim.notify("Not in a codediff view", vim.log.levels.INFO)
    return
  end
  lifecycle.close(tab)
end

-- ============================================================================
-- `nvim -d file1 file2` startup
-- When Nvim was launched in diff mode with file args, open codediff instead.
-- (Only active if this plugin is loaded at startup; e.g. not purely
--  `cmd = "CodeDiff"` lazy-loaded.)
-- ============================================================================
local function on_vim_enter_nvim_d()
  if not config.options.builtin_compat.nvim_d then
    return
  end
  -- `nvim -d` turns on the 'diff' option on the startup windows.
  if not vim.o.diff then
    return
  end

  local argv = vim.fn.argv()
  if #argv < 2 then
    return
  end

  local a, b = argv[1], argv[2]
  if vim.fn.filereadable(a) ~= 1 or vim.fn.filereadable(b) ~= 1 then
    return
  end

  vim.schedule(function()
    -- Do not hijack an already-running codediff session.
    local lifecycle = require("codediff.ui.lifecycle")
    if lifecycle.get_session(vim.api.nvim_get_current_tabpage()) then
      return
    end
    -- The built-in `nvim -d` tab (may hold several diff windows) is left
    -- behind; close it explicitly since :CodeDiff file only cleans up a
    -- leftover single-window argv tab.
    local builtin_tab = vim.api.nvim_get_current_tabpage()
    M.apply_diffopt()
    pcall(function()
      require("codediff.commands").vscode_diff({ fargs = { "file", a, b } })
    end)
    vim.schedule(function()
      local current = vim.api.nvim_get_current_tabpage()
      if vim.api.nvim_tabpage_is_valid(builtin_tab) and builtin_tab ~= current then
        local nr = vim.api.nvim_tabpage_get_number(builtin_tab)
        pcall(vim.cmd, nr .. "tabclose")
      end
    end)
  end)
end

-- ============================================================================
-- Setup: register proxy commands + autocmds. Idempotent.
-- ============================================================================
function M.setup()
  if setup_done then
    return
  end
  setup_done = true

  vim.api.nvim_create_user_command("Diffsplit", cmd_diffsplit, {
    nargs = 1,
    complete = "file",
    desc = "Diff the current buffer with {file} using codediff",
  })
  vim.api.nvim_create_user_command("Diffoff", cmd_diffoff, {
    nargs = 0,
    desc = "Close the codediff view in the current tab",
  })

  local group = vim.api.nvim_create_augroup("CodeDiffBuiltinCompat", { clear = true })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = on_vim_enter_nvim_d,
  })
  -- Live diffopt sync (fires in interactive Nvim; apply_diffopt is the
  -- reliable fallback at entry points for headless/startup contexts).
  vim.api.nvim_create_autocmd("OptionSet", {
    pattern = "diffopt",
    group = group,
    callback = on_option_diffopt,
  })
end

return M
