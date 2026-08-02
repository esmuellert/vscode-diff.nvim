-- Key-sequence normalization for the keymap registry.
--
-- Mapping identity must be canonical: `<Tab>` and `<C-i>` are the same key to
-- Neovim, and `<leader>x` depends on the value of `mapleader` at the moment
-- the mapping is created. Slots are therefore keyed by the fully expanded
-- byte sequence, computed once at claim time and stored, never recomputed.

local M = {}

--- Expand a key sequence to its canonical byte form.
--- @param lhs string
--- @return string|nil canonical nil when lhs is not a usable key sequence
function M.canonical(lhs)
  if type(lhs) ~= "string" or lhs == "" then
    return nil
  end
  local ok, expanded = pcall(vim.api.nvim_replace_termcodes, lhs, true, true, true)
  if not ok or expanded == "" then
    return nil
  end
  return expanded
end

--- Resolve a configured binding value to a key sequence.
--- Preserves the existing contract: a string binds, `false` (or nil, or an
--- empty string) silently disables. No other shape is accepted.
--- @param value string|false|nil
--- @return string|nil lhs
function M.resolve(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end
  return value
end

--- Every key a configured binding asks for.
---
--- An action can be reached by more than one key (`quit = { "q", "<Esc>" }`),
--- so a binding is a list as far as the registry is concerned; a plain string
--- is just the one-key case. `false`, `nil`, `""` and `{}` all mean "do not
--- bind", which is the long-standing way to switch a mapping off.
---
--- Anything else is a mistake the user cannot see -- the value would simply
--- vanish and the action would end up unreachable -- so it comes back with a
--- description of the problem for the caller to report.
--- @param value string|string[]|false|nil
--- @return string[] keys, string|nil problem
function M.keys(value)
  if value == nil or value == false then
    return {}, nil
  end

  if type(value) == "string" then
    if value == "" then
      return {}, nil
    end
    return { value }, nil
  end

  if type(value) ~= "table" then
    return {}, ("expected a key like \"q\", a list like { \"q\", \"<Esc>\" }, or false; got %s"):format(type(value))
  end

  if next(value) == nil then
    return {}, nil
  end

  local keys, seen = {}, {}
  for index, entry in ipairs(value) do
    if type(entry) ~= "string" or entry == "" then
      local what = type(entry) == "string" and "an empty string" or type(entry)
      return {}, ("entry %d of the list is %s; every entry must be a key like \"<Esc>\""):format(index, what)
    end
    if not seen[entry] then
      seen[entry] = true
      table.insert(keys, entry)
    end
  end

  if #keys == 0 then
    return {}, "expected a list of keys like { \"q\", \"<Esc>\" }"
  end
  return keys, nil
end

--- Normalize a mode argument to a list of single-character modes.
--- @param modes string|string[]
--- @return string[]
function M.modes(modes)
  if type(modes) == "table" then
    return modes
  end
  return { modes }
end

return M
