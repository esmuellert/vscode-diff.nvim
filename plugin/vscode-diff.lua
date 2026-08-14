-- Backward compatibility plugin entry point
-- Ensures old :VscodeDiff command still works
if vim.g.loaded_vscode_diff then
  return
end
vim.g.loaded_vscode_diff = 1

-- Ensure codediff is loaded first (it sets up everything)
require("codediff")

-- Create legacy command alias (lazy-loads commands on first invocation)
vim.api.nvim_create_user_command("VscodeDiff", function(opts)
  require("codediff.commands").vscode_diff(opts)
end, {
  nargs = "*",
  bang = true,
  complete = function(arg_lead, cmd_line)
    return require("codediff.commands").complete(arg_lead, cmd_line)
  end,
  desc = "VSCode-style diff view (legacy alias for :CodeDiff)",
})
