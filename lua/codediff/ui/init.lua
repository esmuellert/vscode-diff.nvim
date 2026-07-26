-- Render module facade
local M = {}

local highlights = require("codediff.ui.highlights")
local view = require("codediff.ui.view")
local core = require("codediff.ui.core")
local lifecycle = require("codediff.ui.lifecycle")
-- Eagerly load the scroll-sync manager so it is cached at setup time (like the
-- other UI submodules). It is otherwise required lazily from render/lifecycle
-- code paths that can run after the cwd has changed, where a not-yet-cached
-- module may fail to resolve on a relative runtimepath.
local scroll = require("codediff.ui.scroll")

-- Public functions
M.setup_highlights = highlights.setup
M.create_diff_view = view.create
M.update_diff_view = view.update
M.render_diff = core.render_diff
M.scroll = scroll

-- lifecycle.setup() is called on first view.create() via a once-guard,
-- so autocmds are only registered when actually needed.

return M
