-- Inline diff view engine.
local M = {}

local create = require("codediff.ui.view.inline_view.create")
local update = require("codediff.ui.view.inline_view.update")
local render = require("codediff.ui.view.inline_view.render")
local single_file = require("codediff.ui.view.inline_view.single_file")

M.create = create.create
M.update = update.update
M.rerender = render.rerender
M.show_single_file = single_file.show_single_file
M.show_welcome = single_file.show_welcome

return M
