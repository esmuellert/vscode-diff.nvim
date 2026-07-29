local M = {}
local style_groups = {}
local selected_groups = {}
local next_group = 0

local function expand_short_hex(value)
  if type(value) ~= "string" or not value:match("^#%x%x%x$") then
    return value
  end
  return "#" .. value:sub(2, 2):rep(2) .. value:sub(3, 3):rep(2) .. value:sub(4, 4):rep(2)
end

local function normalize_style(value)
  if type(value) == "string" then
    return { fg = expand_short_hex(value) }
  end
  local style = vim.deepcopy(value)
  for _, key in ipairs({ "fg", "bg", "sp" }) do
    style[key] = expand_short_hex(style[key])
  end
  return style
end

local function generated_group(prefix, key, definition, cache)
  local name = cache[key]
  if not name then
    next_group = next_group + 1
    name = prefix .. next_group
    cache[key] = name
  end
  vim.api.nvim_set_hl(0, name, definition)
  return name
end

local function resolve_base(value)
  if value == nil then
    return "Normal"
  end
  if type(value) == "string" and not value:match("^#%x%x%x$") and not value:match("^#%x%x%x%x%x%x$") then
    return value
  end
  if type(value) ~= "string" and type(value) ~= "table" then
    error("Explorer formatter segment hl must be a highlight group, hex color, or highlight table")
  end

  local style = normalize_style(value)
  return generated_group("CodeDiffExplorerFormat_", vim.inspect(style), style, style_groups)
end

function M.resolve(value, selected_bg)
  local base = resolve_base(value)
  if not selected_bg then
    return base
  end
  local definition = vim.api.nvim_get_hl(0, { name = base, link = false })
  definition.bg = selected_bg
  local key = base .. ":" .. selected_bg
  return generated_group("CodeDiffExplorerSelectedFormat_", key, definition, selected_groups)
end

return M
