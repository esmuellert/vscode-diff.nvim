-- Conflict resolution actions for merge tool
-- Handles accept current/incoming/both/none actions
local M = {}

-- Import submodules
local tracking = require("codediff.ui.conflict.tracking")
local signs = require("codediff.ui.conflict.signs")
local resolution = require("codediff.ui.conflict.resolution")
local navigation = require("codediff.ui.conflict.navigation")
local keymaps = require("codediff.ui.conflict.keymaps")

-- Delegate to tracking module
M.run_repeatable_action = tracking.run_repeatable_action
M.initialize_tracking = tracking.initialize_tracking

-- Delegate to signs module
M.refresh_all_conflict_signs = signs.refresh_all_conflict_signs
M.setup_sign_refresh_autocmd = signs.setup_sign_refresh_autocmd

-- Delegate to resolution module
M.accept_incoming = resolution.accept_incoming
M.accept_current = resolution.accept_current
M.accept_both = resolution.accept_both
M.discard = resolution.discard
M.accept_all_incoming = resolution.accept_all_incoming
M.accept_all_current = resolution.accept_all_current
M.accept_all_both = resolution.accept_all_both
M.discard_all = resolution.discard_all
M.diffget_incoming = resolution.diffget_incoming
M.diffget_current = resolution.diffget_current

-- Delegate to navigation module
M.navigate_next_conflict = navigation.navigate_next_conflict
M.navigate_prev_conflict = navigation.navigate_prev_conflict

-- Delegate to keymaps module
M.setup_keymaps = keymaps.setup_keymaps

return M
