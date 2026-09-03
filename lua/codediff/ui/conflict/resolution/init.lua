-- Conflict resolution commands for one block or a whole file.
local M = {}

local block = require("codediff.ui.conflict.resolution.block")
local file = require("codediff.ui.conflict.resolution.file")
local diffget = require("codediff.ui.conflict.resolution.diffget")

M.accept_incoming = block.accept_incoming
M.accept_current = block.accept_current
M.accept_both = block.accept_both
M.discard = block.discard
M.accept_all_incoming = file.accept_all_incoming
M.accept_all_current = file.accept_all_current
M.accept_all_both = file.accept_all_both
M.discard_all = file.discard_all
M.diffget_incoming = diffget.diffget_incoming
M.diffget_current = diffget.diffget_current

return M
