-- vscode-diff main API
local M = {}

-- Configuration setup
function M.setup(opts)
  local config = require("codediff.config")
  config.setup(opts)

  local render = require("codediff.ui")
  render.setup_highlights()
end

-- Open a directory diff, optionally restricted to a list of relative paths.
-- dir1 = "original", dir2 = "modified".
-- opts.paths: list of relative paths to compare. When provided, only those
--   paths are diffed (each stat'd directly rather than scanning the trees);
--   a path missing on one side shows as a creation/deletion, and paths missing
--   on both sides are reported via a warning and ignored. Omit for a full diff.
-- opts.layout: "inline" | "side-by-side" (optional).
-- Example:
--   require("codediff").dir_diff("/a", "/b", { paths = { "src/x.lua", "README" } })
function M.dir_diff(dir1, dir2, opts)
  return require("codediff.commands").dir_diff(dir1, dir2, opts)
end

-- Navigate to next hunk in the current diff view
-- Returns true if navigation succeeded, false otherwise
function M.next_hunk()
  local navigation = require("codediff.ui.view.navigation")
  return navigation.next_hunk()
end

-- Navigate to previous hunk in the current diff view
-- Returns true if navigation succeeded, false otherwise
function M.prev_hunk()
  local navigation = require("codediff.ui.view.navigation")
  return navigation.prev_hunk()
end

-- Navigate to next file in explorer/history mode
-- In single-file history mode, navigates to next commit instead
-- Returns true if navigation succeeded, false otherwise
function M.next_file()
  local navigation = require("codediff.ui.view.navigation")
  return navigation.next_file()
end

-- Navigate to previous file in explorer/history mode
-- In single-file history mode, navigates to previous commit instead
-- Returns true if navigation succeeded, false otherwise
function M.prev_file()
  local navigation = require("codediff.ui.view.navigation")
  return navigation.prev_file()
end

return M
