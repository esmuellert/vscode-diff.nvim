-- Plugin entry point - auto-loaded by Neovim
-- Only loads lightweight modules at startup; heavy modules (UI, diff engine,
-- explorer, history) are deferred until first :CodeDiff invocation.
if vim.g.loaded_codediff then
  return
end
vim.g.loaded_codediff = 1

-- Lightweight startup: highlights (~0.3ms) + virtual file scheme (~0.1ms)
local highlights = require("codediff.ui.highlights")
local virtual_file = require('codediff.core.virtual_file')

virtual_file.setup()
highlights.setup()

-- Re-apply highlights on ColorScheme change
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("CodeDiffHighlights", { clear = true }),
  callback = function()
    highlights.setup()
  end,
})

-- Cache for revision candidates (avoid repeated git calls during rapid completions)
local rev_cache = {
  candidates = nil,
  git_root = nil,
  timestamp = 0,
  ttl = 5,  -- Cache for 5 seconds
}

local function get_cached_rev_candidates(git_root)
  local git = require('codediff.core.git')
  local now = vim.loop.now() / 1000  -- Convert to seconds
  if rev_cache.candidates
      and rev_cache.git_root == git_root
      and (now - rev_cache.timestamp) < rev_cache.ttl then
    return rev_cache.candidates
  end

  local candidates = git.get_rev_candidates(git_root)
  rev_cache.candidates = candidates
  rev_cache.git_root = git_root
  rev_cache.timestamp = now
  return candidates
end

-- Filter a list of flag candidates by prefix match against arg_lead
local function complete_flags(candidates, arg_lead)
  local filtered = {}
  for _, flag in ipairs(candidates) do
    if flag:find(arg_lead, 1, true) == 1 then
      table.insert(filtered, flag)
    end
  end
  if #filtered > 0 then
    return filtered
  end
  return nil
end

-- Register user command with subcommand completion
local function complete_codediff(arg_lead, cmd_line, _)
  local git = require('codediff.core.git')
  local commands = require("codediff.commands")
  local args = vim.split(cmd_line, "%s+", { trimempty = true })

  -- If no args or just ":CodeDiff", suggest subcommands and revisions
  if #args <= 1 then
    local candidates = vim.list_extend({}, commands.SUBCOMMANDS)
    local cwd = vim.fn.getcwd()
    local git_root = git.get_git_root_sync(cwd)
    local rev_candidates = get_cached_rev_candidates(git_root)
    if rev_candidates then
      vim.list_extend(candidates, rev_candidates)
    end
    return candidates
  end

  -- If first arg is "merge" or "file", complete with file paths
  local first_arg = args[2]
  if first_arg == "merge" or first_arg == "file" then
    return vim.fn.getcompletion(arg_lead, "file")
  end

  -- Flag completion for subcommands
  if arg_lead:match("^%-") then
    if first_arg == "history" then
      local result = complete_flags({ "--reverse", "-r", "--base", "-b", "--inline", "--side-by-side" }, arg_lead)
      if result then return result end
    end

    -- Layout flags available for all subcommands
    local result = complete_flags({ "--inline", "--side-by-side", "--exit-on-close" }, arg_lead)
    if result then return result end
  end

  -- For revision arguments, suggest git refs filtered by arg_lead
  if #args == 2 and arg_lead ~= "" then
    local cwd = vim.fn.getcwd()
    local git_root = git.get_git_root_sync(cwd)
    local rev_candidates = get_cached_rev_candidates(git_root)
    local filtered = {}

    -- Check if user is typing a triple-dot pattern (e.g., "main...")
    local base_rev = arg_lead:match("^(.+)%.%.%.$")
    if base_rev then
      -- User typed "main...", suggest completing with refs or leave as-is
      if rev_candidates then
        for _, candidate in ipairs(rev_candidates) do
          table.insert(filtered, base_rev .. "..." .. candidate)
        end
      end
      -- Also include the bare triple-dot (compares to working tree)
      table.insert(filtered, 1, arg_lead)
      return filtered
    end

    -- Normal completion: match refs and also suggest triple-dot variants
    if rev_candidates then
      for _, candidate in ipairs(rev_candidates) do
        if candidate:find(arg_lead, 1, true) == 1 then
          table.insert(filtered, candidate)
          -- Also suggest the merge-base variant
          table.insert(filtered, candidate .. "...")
        end
      end
    end
    if #filtered > 0 then
      return filtered
    end
  end

  -- Otherwise default file completion
  return vim.fn.getcompletion(arg_lead, "file")
end

vim.api.nvim_create_user_command("CodeDiff", function(opts)
  require("codediff.commands").vscode_diff(opts)
end, {
  nargs = "*",
  bang = true,
  range = true,
  complete = complete_codediff,
  desc = "VSCode-style diff view: :CodeDiff [<revision>] | merge <file> | file <revision> | install"
})
