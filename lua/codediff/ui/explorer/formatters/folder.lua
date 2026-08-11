-- Default folder row: `[indent] [icon] name`.

local common = require("codediff.ui.explorer.formatters.common")

return function(ctx)
  return {
    left = {
      { segments = common.prefix(ctx) },
      {
        segments = { { text = ctx.name, hl = "Directory" } },
        truncate_priority = 1,
      },
    },
    right = {},
    min_gap = 2,
  }
end
