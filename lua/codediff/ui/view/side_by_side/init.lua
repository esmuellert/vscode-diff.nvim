-- Side-by-side diff view engine.
local M = {}

-- Eagerly load explorer and history to avoid lazy require failures
-- when CWD changes in vim.schedule callbacks.
local explorer_module = require("codediff.ui.explorer")
local history_module = require("codediff.ui.history")

local create = require("codediff.ui.view.side_by_side.create")
local update = require("codediff.ui.view.side_by_side.update")
local single_file = require("codediff.ui.view.side_by_side.single_file")

M.create = create.create
M.update = update.update
M.show_untracked_file = single_file.show_untracked_file
M.show_deleted_file = single_file.show_deleted_file
M.show_added_virtual_file = single_file.show_added_virtual_file
M.show_deleted_virtual_file = single_file.show_deleted_virtual_file
M.show_welcome = single_file.show_welcome

return M
