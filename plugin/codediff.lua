-- Plugin entry point - auto-loaded by Neovim
-- Only loads lightweight modules at startup; heavy modules (UI, diff engine,
-- explorer, history) are deferred until first :CodeDiff invocation.
if vim.g.loaded_codediff then
  return
end
vim.g.loaded_codediff = 1

-- Lightweight startup: highlights (~0.3ms) + virtual file scheme (~0.1ms)
local highlights = require("codediff.ui.highlights")
local virtual_file = require("codediff.core.virtual_file")

virtual_file.setup()
highlights.setup()

-- Re-apply highlights on ColorScheme change
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("CodeDiffHighlights", { clear = true }),
  callback = function()
    highlights.setup()
  end,
})

-- Completion is derived from the argparse command tree (see commands.complete).

vim.api.nvim_create_user_command("CodeDiff", function(opts)
  require("codediff.commands").vscode_diff(opts)
end, {
  nargs = "*",
  bang = true,
  range = true,
  complete = function(arg_lead, cmd_line)
    return require("codediff.commands").complete(arg_lead, cmd_line)
  end,
  desc = "Live code review workspace for Neovim",
})
