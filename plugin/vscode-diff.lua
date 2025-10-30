-- Plugin entry point for lazy.nvim or other plugin managers
-- This file is loaded automatically when the plugin is loaded

if vim.g.loaded_vscode_diff then
  return
end
vim.g.loaded_vscode_diff = 1

-- Setup highlight groups
local render = require("vscode-diff.render")
render.setup_highlights()

-- Create user command
vim.api.nvim_create_user_command("VscodeDiff", function(opts)
  local args = opts.fargs

  -- Two modes:
  -- 1. :VscodeDiff <file_a> <file_b> - Compare two files
  -- 2. :VscodeDiff <revision> - Compare current buffer with git revision

  if #args == 0 then
    vim.notify("Usage: :VscodeDiff <file_a> <file_b> OR :VscodeDiff <revision>", vim.log.levels.ERROR)
    return
  end

  -- Mode 2: Git diff (single argument)
  if #args == 1 then
    local revision = args[1]
    local current_file = vim.api.nvim_buf_get_name(0)

    -- Check if current buffer has a file
    if current_file == "" then
      vim.notify("Current buffer is not a file", vim.log.levels.ERROR)
      return
    end

    -- Check if file is in a git repository
    local git = require("vscode-diff.git")
    if not git.is_in_git_repo(current_file) then
      vim.notify("Current file is not in a git repository", vim.log.levels.ERROR)
      return
    end

    -- Get current buffer content
    local lines_current = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    -- Get file content from git revision (async)
    git.get_file_at_revision(revision, current_file, function(err, lines_git)
      vim.schedule(function()
        if err then
          vim.notify(err, vim.log.levels.ERROR)
          return
        end

        -- Compute diff using new diff.lua
        local diff = require("vscode-diff.diff")
        local lines_diff = diff.compute_diff(lines_git, lines_current)

        -- Render using new render.lua
        render.create_diff_view(lines_git, lines_current, lines_diff)
      end)
    end)

    return
  end

  -- Mode 1: File diff (two arguments)
  if #args ~= 2 then
    vim.notify("Usage: :VscodeDiff <file_a> <file_b> OR :VscodeDiff <revision>", vim.log.levels.ERROR)
    return
  end

  local file_a = args[1]
  local file_b = args[2]

  -- Read files
  local lines_a = vim.fn.readfile(file_a)
  local lines_b = vim.fn.readfile(file_b)

  -- Compute diff using new diff.lua
  local diff = require("vscode-diff.diff")
  local lines_diff = diff.compute_diff(lines_a, lines_b)

  -- Render using new render.lua
  render.create_diff_view(lines_a, lines_b, lines_diff)
end, {
  nargs = "*",
  complete = "file",
  desc = "VSCode-style diff view (files or git revision)"
})

print("vscode-diff.nvim loaded")
