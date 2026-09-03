-- Three-way merge calculations for conflict views.
local M = {}

local fillers = require("codediff.ui.conflict.merge.fillers")
local auto_merge = require("codediff.ui.conflict.merge.auto_merge")

M.compute_merge_fillers = fillers.compute_merge_fillers
M.compute_merge_fillers_and_conflicts = fillers.compute_merge_fillers_and_conflicts
M.compute_auto_merged_result = auto_merge.compute_auto_merged_result

return M
