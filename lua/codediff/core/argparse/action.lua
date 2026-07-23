-- ArgAction: what happens when an argument is encountered during parsing.
-- Mirrors clap's ArgAction enum (Set / SetTrue / SetFalse / Append / Count).
local M = {
  -- Store the (single) value, replacing any previous value.
  SET = "set",
  -- Boolean flag: set the value to true when present.
  SET_TRUE = "set_true",
  -- Boolean flag: set the value to false when present.
  SET_FALSE = "set_false",
  -- Collect every occurrence into a list.
  APPEND = "append",
  -- Count the number of occurrences.
  COUNT = "count",
}

-- Does this action consume a value from the argument list?
function M.takes_value(a)
  return a == M.SET or a == M.APPEND
end

return M
