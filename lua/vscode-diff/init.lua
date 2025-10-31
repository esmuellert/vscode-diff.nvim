-- vscode-diff main API
local M = {}

local config = require("vscode-diff.config")
local diff = require("vscode-diff.diff")
local render = require("vscode-diff.render")
local git = require("vscode-diff.git")

-- Configuration setup
function M.setup(opts)
  config.setup(opts)
end

-- Re-export diff module
M.compute_diff = diff.compute_diff
M.get_version = diff.get_version

-- Re-export render module
M.setup_highlights = render.setup_highlights
M.render_diff = render.render_diff
M.create_diff_view = render.create_diff_view

-- Re-export git module
M.is_in_git_repo = git.is_in_git_repo
M.get_file_at_revision = git.get_file_at_revision

return M
