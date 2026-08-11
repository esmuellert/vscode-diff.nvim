-- Default group row: `[folder-icon] label (N · +42 -8)`.
-- The `· +42 -8` suffix renders only when `explorer.line_stats.enabled = true`
-- populates `ctx.stats`.

local stats = require("codediff.ui.explorer.formatters.stats")

return function(ctx)
  return {
    left = {
      { segments = { { text = " ", hl = "CodeDiffExplorerTreeGroup" } } },
      {
        segments = { { text = ctx.label, hl = "CodeDiffExplorerTreeGroup" } },
        truncate_priority = 2,
      },
      {
        segments = stats.group_summary(ctx),
        truncate_priority = 1,
      },
    },
    right = {},
    min_gap = 2,
  }
end
