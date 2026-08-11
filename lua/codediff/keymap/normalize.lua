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

--- Read a binding as the list of keys it asks for.
---
--- Bindings that come from config arrive already validated as a list (see
--- codediff.keymap.resolve); a plain string is accepted too, for the handful
--- of mappings that are not configurable, such as the explorer's double click.
--- @param value string|string[]|false|nil
--- @return string[]
function M.key_list(value)
  if type(value) == "table" then
    return value
  end
  if type(value) ~= "string" or value == "" then
    return {}
  end
  return { value }
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
