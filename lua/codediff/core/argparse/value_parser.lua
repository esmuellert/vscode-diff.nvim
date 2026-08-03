-- ValueParser: validates and coerces a raw string argument into a typed value.
-- Mirrors clap's ValueParser / value_parser! Each parser is a table
--   { name = string, parse = fn(raw) -> value | (nil, err_detail), choices? }
-- so help/completion can introspect (e.g. enum choices).
local M = {}

local function make(name, fn, extra)
  local vp = { name = name, parse = fn }
  if extra then
    for k, v in pairs(extra) do
      vp[k] = v
    end
  end
  return vp
end

-- Identity: any string is accepted.
M.string = make("string", function(raw)
  return raw
end)

-- Integer (rejects fractions and non-numbers).
M.int = make("int", function(raw)
  local n = tonumber(raw)
  if not n or n ~= math.floor(n) then
    return nil, "expected an integer, got '" .. raw .. "'"
  end
  return n
end)

-- Any number (integer or float).
M.number = make("number", function(raw)
  local n = tonumber(raw)
  if not n then
    return nil, "expected a number, got '" .. raw .. "'"
  end
  return n
end)

-- Boolean from common truthy/falsy spellings.
M.boolean = make("boolean", function(raw)
  local low = raw:lower()
  if low == "true" or low == "1" or low == "yes" then
    return true
  end
  if low == "false" or low == "0" or low == "no" then
    return false
  end
  return nil, "expected a boolean, got '" .. raw .. "'"
end)

-- Enum: value must be one of `choices`.
function M.enum(choices)
  local set = {}
  for _, c in ipairs(choices) do
    set[c] = true
  end
  return make("enum", function(raw)
    if set[raw] then
      return raw
    end
    return nil, "expected one of {" .. table.concat(choices, ", ") .. "}, got '" .. raw .. "'"
  end, { choices = choices })
end

-- Alias matching clap's naming.
M.one_of = M.enum

-- Wrap a custom function: fn(raw) -> value | (nil, err_detail).
function M.custom(fn, name)
  return make(name or "custom", fn)
end

return M
