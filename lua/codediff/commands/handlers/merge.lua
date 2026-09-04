-- :CodeDiff merge <file> -- the three-way merge view for a conflicted file.
local M = {}

local git = require("codediff.core.git")
local config = require("codediff.config")
local view = require("codediff.ui.view")
local path = require("codediff.core.path")

function M.run(opts, global_opts)
  global_opts = global_opts or {}
  local args = opts.fargs
  if #args == 0 then
    vim.notify("Usage: :CodeDiff merge <filename>", vim.log.levels.ERROR)
    return
  end

  local filename = args[1]
  -- Strip surrounding quotes if present (from shell escaping in git mergetool)
  filename = filename:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")

  -- Resolve to absolute path
  local full_path = vim.fn.fnamemodify(filename, ":p")

  if vim.fn.filereadable(full_path) == 0 then
    vim.notify("File not found: " .. filename, vim.log.levels.ERROR)
    return
  end

  -- Ensure all required modules are loaded before we start vim.wait
  -- This prevents issues with lazy-loading during the wait loop

  -- For synchronous execution (required by git mergetool), we need to block
  -- until the view is ready. Use vim.wait which processes the event loop.
  local view_ready = false
  local error_msg = nil

  git.get_git_root(full_path, function(err_root, git_root)
    if err_root then
      error_msg = "Not a git repository: " .. err_root
      view_ready = true
      return
    end

    local relative_path = git.get_relative_path(full_path, git_root)

    -- Schedule everything that needs main thread (vim.filetype.match, view.create)
    vim.schedule(function()
      local filetype = vim.filetype.match({ filename = full_path }) or ""

      -- Determine conflict buffer positions based on config
      -- conflict_ours_position controls where :2 (OURS) appears on screen
      local ours_position = config.options.diff.conflict_ours_position or "right"

      -- After the conflict view's win_splitmove(rightbelow=false):
      -- - original_win is on LEFT
      -- - modified_win is on RIGHT
      local original_rev, modified_rev
      if ours_position == "right" then
        original_rev = ":3" -- THEIRS in original_win (LEFT)
        modified_rev = ":2" -- OURS in modified_win (RIGHT)
      else
        original_rev = ":2" -- OURS in original_win (LEFT)
        modified_rev = ":3" -- THEIRS in modified_win (RIGHT)
      end

      ---@type SessionConfig
      local session_config = {
        panel = nil,
        git_root = git_root,
        original = path.make_ref(relative_path, git_root),
        modified = path.make_ref(relative_path, git_root),
        original_revision = original_rev,
        modified_revision = modified_rev,
        conflict = true,
        exit_on_close = global_opts.exit_on_close,
      }

      view.create(session_config, filetype, function()
        view_ready = true
      end)
    end)
  end)

  -- Block until view is ready - this allows event loop to process callbacks
  vim.wait(10000, function()
    return view_ready
  end, 10)

  -- Force screen redraw after vim.wait to ensure all windows are visible
  vim.cmd("redraw!")

  if error_msg then
    vim.notify(error_msg, vim.log.levels.ERROR)
  end
end

-- ── Command tree (argparse) ────────────────────────────────────────────────
-- The :CodeDiff grammar is declared once as an argparse Command tree. The
-- handlers reproduce the previous dispatch exactly; revision/file/dir and
-- triple-dot detection stays in the handlers because it touches the filesystem.

-- Translate global flags into the { layout, exit_on_close } table handlers expect.

return M
