-- Three-pane conflict editor rendering.
local M = {}

local inputs = require("codediff.ui.conflict.view.inputs")
local result = require("codediff.ui.conflict.view.result")

M.compute_and_render_conflict = inputs.compute_and_render_conflict
M.setup_conflict_result_window = result.setup_conflict_result_window

return M
