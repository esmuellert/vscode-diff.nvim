-- :CodeDiff dir <a> <b> -- two directories, listed in the explorer.
local M = {}

local view = require("codediff.ui.view")
local path = require("codediff.core.path")

function M.run(dir1, dir2, global_opts)
  local dir_mod = require("codediff.core.dir")

  -- Expand ~ and environment variables in paths
  dir1 = vim.fn.expand(dir1)
  dir2 = vim.fn.expand(dir2)

  if vim.fn.isdirectory(dir1) == 0 then
    vim.notify("Not a directory: " .. dir1, vim.log.levels.ERROR)
    return
  end
  if vim.fn.isdirectory(dir2) == 0 then
    vim.notify("Not a directory: " .. dir2, vim.log.levels.ERROR)
    return
  end

  local diff = dir_mod.diff_directories(dir1, dir2)
  local status_result = diff.status_result

  if #status_result.unstaged == 0 and #status_result.staged == 0 then
    vim.notify("No differences between directories", vim.log.levels.INFO)
    return
  end

  ---@type SessionConfig
  local session_config = {
    panel = { name = "explorer", data = { status_result = status_result } },
    git_root = nil, -- nil signals non-git (directory) mode
    original = path.make_ref(diff.root1, nil),
    modified = path.make_ref(diff.root2, nil),
    original_revision = nil,
    modified_revision = nil,
    layout = global_opts.layout,
    exit_on_close = global_opts.exit_on_close,
  }

  view.create(session_config, "")
end

-- Handle file history command
-- range: git range (e.g., "origin/main..HEAD", "HEAD~10")
-- file_path: optional file path to filter history
-- line_range: optional {start, end} for line-range history (git log -L)

return M
