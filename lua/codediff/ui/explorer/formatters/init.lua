-- Default explorer row formatters.
--
-- Used when `explorer.formatters.{file,folder,group}` is nil. Users can also
-- `require("codediff.ui.explorer.formatters")` to grab these defaults and wrap
-- them in a custom formatter.
--
-- Layout:
--   init.lua    - module entry: re-exports the three default row functions.
--   common.lua  - helpers shared across row types (indent + icon prefix).
--   stats.lua   - line-stats rendering, active only when
--                 `explorer.line_stats.enabled = true` populates `ctx.stats`.
--   file.lua    - default file row.
--   folder.lua  - default folder row.
--   group.lua   - default group row.

local M = {}

M.file = require("codediff.ui.explorer.formatters.file")
M.folder = require("codediff.ui.explorer.formatters.folder")
M.group = require("codediff.ui.explorer.formatters.group")

return M
