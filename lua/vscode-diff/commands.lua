-- Command implementations for vscode-diff
local M = {}

local git = require("vscode-diff.git")
local diff = require("vscode-diff.diff")
local render = require("vscode-diff.render")

local function handle_git_diff(revision)
  local current_file = vim.api.nvim_buf_get_name(0)

  if current_file == "" then
    vim.notify("Current buffer is not a file", vim.log.levels.ERROR)
    return
  end

  if not git.is_in_git_repo(current_file) then
    vim.notify("Current file is not in a git repository", vim.log.levels.ERROR)
    return
  end

  local lines_current = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  git.get_file_at_revision(revision, current_file, function(err, lines_git)
    vim.schedule(function()
      if err then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end

      local lines_diff = diff.compute_diff(lines_git, lines_current)
      render.create_diff_view(lines_git, lines_current, lines_diff)
    end)
  end)
end

local function handle_file_diff(file_a, file_b)
  local lines_a = vim.fn.readfile(file_a)
  local lines_b = vim.fn.readfile(file_b)

  local lines_diff = diff.compute_diff(lines_a, lines_b)
  render.create_diff_view(lines_a, lines_b, lines_diff)
end

function M.vscode_diff(opts)
  local args = opts.fargs

  if #args == 0 then
    vim.notify("Usage: :VscodeDiff <file_a> <file_b> OR :VscodeDiff <revision>", vim.log.levels.ERROR)
    return
  end

  if #args == 1 then
    handle_git_diff(args[1])
  elseif #args == 2 then
    handle_file_diff(args[1], args[2])
  else
    vim.notify("Usage: :VscodeDiff <file_a> <file_b> OR :VscodeDiff <revision>", vim.log.levels.ERROR)
  end
end

return M
