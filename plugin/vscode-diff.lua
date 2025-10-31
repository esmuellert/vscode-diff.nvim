-- Plugin entry point - auto-loaded by Neovim
if vim.g.loaded_vscode_diff then
  return
end
vim.g.loaded_vscode_diff = 1

local render = require("vscode-diff.render")
local commands = require("vscode-diff.commands")

-- Setup highlights
render.setup_highlights()

-- Register user command
vim.api.nvim_create_user_command("VscodeDiff", commands.vscode_diff, {
  nargs = "*",
  complete = "file",
  desc = "VSCode-style diff view (files or git revision)"
})
