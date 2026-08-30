-- Argument handling shared by the command handlers.
local M = {}

local git = require("codediff.core.git")

--- Report a git error and answer whether there was one, so a callback can say
--- `if parse.failed(err) then return end`. Scheduled because git callbacks run
--- off the main loop, where notify is not safe.
--- @param err string|nil
--- @param message (string|fun(err: string): string)? Overrides the error text.
---   Pass a function when building it would index `err`, which is nil here on
---   the success path.
--- @return boolean
function M.failed(err, message)
  if not err then
    return false
  end
  local text = err
  if type(message) == "function" then
    text = message(err)
  elseif message then
    text = message
  end
  vim.schedule(function()
    vim.notify(text, vim.log.levels.ERROR)
  end)
  return true
end

--- Parse triple-dot syntax for merge-base comparisons.
-- @param arg string: The argument to parse
-- @return string|nil, string|nil: base_rev, target_rev (nil if not triple-dot syntax)
function M.parse_triple_dot(arg)
  if not arg then
    return nil, nil
  end
  local base, target = arg:match("^(.+)%.%.%.(.*)$")
  if base then
    return base, target ~= "" and target or nil
  end
  return nil, nil
end

-- Resolve the git root for "working repo" modes (explorer, history) and call
-- on_ok(git_root, is_override). Resolution order: the --repo/-C override, else
-- the current buffer's file, else cwd. This is the single place the --repo/-C
-- override is applied for these modes.

-- Resolve the git root for "working repo" modes (explorer, history) and call
-- on_ok(git_root, is_override). Resolution order: the --repo/-C override, else
-- the current buffer's file, else cwd. This is the single place the --repo/-C
-- override is applied for these modes.
function M.resolve_working_root(global_opts, on_ok)
  local override = global_opts and global_opts.repo
  if override then
    git.get_git_root(override, function(err, git_root)
      if M.failed(err, "Not a git repository: " .. override) then
        return
      end
      on_ok(git_root, true)
    end)
    return
  end

  local current_file = vim.api.nvim_buf_get_name(0)
  local cwd = vim.fn.getcwd()
  if current_file ~= "" then
    git.get_git_root(current_file, function(err_file, git_root_file)
      if not err_file then
        on_ok(git_root_file, false)
        return
      end
      -- Buffer path failed, fall back to cwd
      git.get_git_root(cwd, function(err_cwd, git_root_cwd)
        if not err_cwd then
          on_ok(git_root_cwd, false)
          return
        end
        vim.schedule(function()
          vim.notify("Not in a git repository", vim.log.levels.ERROR)
        end)
      end)
    end)
  else
    git.get_git_root(cwd, function(err_cwd, git_root)
      if M.failed(err_cwd) then
        return
      end
      on_ok(git_root, false)
    end)
  end
end

--- Handles diffing the current buffer against a given git revision.
-- @param revision string: The git revision (e.g., "HEAD", commit hash, branch name) to compare the current file against.
-- @param revision2 string?: Optional second revision. If provided, compares revision vs revision2.
-- @param global_opts table?: Global options (e.g., { layout = "inline" })
-- This function chains async git operations to get git root, resolve revision to hash, and get file content.

-- ── Command tree (argparse) ────────────────────────────────────────────────
-- The :CodeDiff grammar is declared once as an argparse Command tree. The
-- handlers reproduce the previous dispatch exactly; revision/file/dir and
-- triple-dot detection stays in the handlers because it touches the filesystem.

-- Translate global flags into the { layout, exit_on_close } table handlers expect.
function M.to_global_opts(m)
  local layout
  if m:get_flag("inline") then
    layout = "inline"
  elseif m:get_flag("side_by_side") then
    layout = "side-by-side"
  end
  -- Expand ~ and env vars in the --repo/-C path once, here at the boundary, so
  -- every consumer gets a filesystem-ready seed for git-root resolution.
  local repo = m:get_one("repo")
  repo = repo and repo ~= "" and vim.fn.expand(repo) or nil
  return { layout = layout, exit_on_close = m:get_flag("exit_on_close") or nil, repo = repo }
end

-- Expand % (current file) and ~/env in a path argument.

-- Expand % (current file) and ~/env in a path argument.
function M.expand_arg_path(p)
  if p == "%" then
    return vim.api.nvim_buf_get_name(0)
  end
  return vim.fn.expand(p)
end

return M
