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
  
  if #args ~= 2 then
    vim.notify("Usage: :VscodeDiff <file_a> <file_b>", vim.log.levels.ERROR)
    return
  end
  
  local file_a = args[1]
  local file_b = args[2]
  
  -- Read files
  local lines_a = vim.fn.readfile(file_a)
  local lines_b = vim.fn.readfile(file_b)
  
  -- Compute diff
  local diff = require("vscode-diff")
  local plan = diff.compute_diff(lines_a, lines_b)
  
  -- Render
  render.render_diff(lines_a, lines_b, plan)
end, {
  nargs = "*",
  complete = "file",
  desc = "VSCode-style diff view"
})

print("vscode-diff.nvim loaded")
