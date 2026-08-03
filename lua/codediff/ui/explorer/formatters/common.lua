-- Helpers shared across multiple default row formatters. Always active,
-- independent of any explorer feature toggles.

local M = {}

-- Row prefix: indent + optional icon + trailing space.
function M.prefix(ctx)
  local segments = { { text = ctx.indent, hl = ctx.indent_hl } }
  if ctx.icon ~= "" then
    segments[#segments + 1] = { text = ctx.icon, hl = ctx.icon_hl }
    segments[#segments + 1] = { text = " ", hl = "Normal" }
  end
  return segments
end

return M
