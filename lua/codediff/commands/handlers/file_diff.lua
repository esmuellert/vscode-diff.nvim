-- :CodeDiff file <a> <b> -- two paths on disk.
local M = {}

local view = require("codediff.ui.view")
local path = require("codediff.core.path")

function M.run(file_a, file_b, global_opts)
  -- Determine filetype from first file
  local filetype = vim.filetype.match({ filename = file_a }) or ""

  -- Snapshot state before creating diff tab (for argv cleanup below)
  local prev_tab = vim.api.nvim_get_current_tabpage()
  local prev_tab_bufs = vim.api.nvim_tabpage_list_wins(prev_tab)
  local is_single_win_tab = #prev_tab_bufs == 1

  -- Create diff view (no pre-reading needed, :edit will load content)
  ---@type SessionConfig
  local session_config = {
    panel = nil,
    git_root = nil,
    original = path.make_ref(file_a, nil),
    modified = path.make_ref(file_b, nil),
    original_revision = nil,
    modified_revision = nil,
    layout = global_opts.layout,
    exit_on_close = global_opts.exit_on_close,
  }
  view.create(session_config, filetype)

  -- Clean up leftover tab from command-line args (git difftool scenario).
  -- When invoked as `nvim "$LOCAL" "$REMOTE" +"CodeDiff file ..."`, neovim
  -- creates a tab with the first argv file. Now that the diff tab exists,
  -- that original tab is redundant. Close it remotely (without switching to
  -- it) and defer to avoid interfering with startup autocmds / persistence.
  -- Guard: only trigger when argv files match the diff files (so running
  -- `:CodeDiff file a b` from an existing session won't close unrelated tabs).
  local argc = vim.fn.argc()
  if argc == 2 and is_single_win_tab then
    local argv0 = vim.fn.fnamemodify(vim.fn.argv(0), ":p")
    local argv1 = vim.fn.fnamemodify(vim.fn.argv(1), ":p")
    local abs_a = vim.fn.fnamemodify(file_a, ":p")
    local abs_b = vim.fn.fnamemodify(file_b, ":p")
    local argv_matches = (argv0 == abs_a and argv1 == abs_b) or (argv0 == abs_b and argv1 == abs_a)
    if argv_matches then
      vim.schedule(function()
        if vim.api.nvim_tabpage_is_valid(prev_tab) and prev_tab ~= vim.api.nvim_get_current_tabpage() then
          local tab_nr = vim.api.nvim_tabpage_get_number(prev_tab)
          vim.cmd(tab_nr .. "tabclose")
        end
        pcall(vim.cmd, "%argdelete")
      end)
    end
  end
end

return M
