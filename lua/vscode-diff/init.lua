-- vscode-diff main interface
-- Re-exports diff.lua and render.lua for convenience

local M = {}

-- Re-export diff module
local diff = require("vscode-diff.diff")
M.compute_diff = diff.compute_diff
M.get_version = diff.get_version

-- Re-export render module
local render = require("vscode-diff.render")
M.setup_highlights = render.setup_highlights
M.render_diff = render.render_diff
M.create_diff_view = render.create_diff_view

return M
