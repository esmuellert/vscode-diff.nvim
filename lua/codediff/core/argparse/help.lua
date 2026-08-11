-- Auto-generated usage and help text from a Command tree. Mirrors clap's help
-- generation (kept plain: Neovim renders to :messages / a scratch buffer).
local action = require("codediff.core.argparse.action")

local M = {}

local function split_args(command)
  local positionals, options = {}, {}
  for _, arg in ipairs(command._args) do
    if arg:is_positional() then
      table.insert(positionals, arg)
    else
      table.insert(options, arg)
    end
  end
  return positionals, options
end

local function option_label(arg)
  local names = {}
  if arg._short then
    table.insert(names, "-" .. arg._short)
  end
  if arg._long then
    table.insert(names, "--" .. arg._long)
  end
  local label = table.concat(names, ", ")
  if arg:takes_value() then
    label = label .. " <" .. (arg._value_name or arg.id:upper()) .. ">"
  end
  return label
end

local function positional_token(arg)
  local name = "<" .. (arg._value_name or arg.id) .. ">"
  if arg._action == action.APPEND then
    name = name .. "..."
  end
  return name
end

-- Single-line usage string.
function M.usage(command, prog)
  local parts = { prog or command._name }
  local positionals, options = split_args(command)
  for _, arg in ipairs(options) do
    local token = arg:display_name()
    if arg:takes_value() then
      token = token .. " <" .. (arg._value_name or arg.id:upper()) .. ">"
    end
    if not arg._required then
      token = "[" .. token .. "]"
    end
    table.insert(parts, token)
  end
  if #command._subcommand_order > 0 then
    table.insert(parts, "<" .. table.concat(command._subcommand_order, "|") .. ">")
  end
  for _, arg in ipairs(positionals) do
    local token = positional_token(arg)
    if not arg._required then
      token = "[" .. token .. "]"
    end
    table.insert(parts, token)
  end
  return table.concat(parts, " ")
end

-- Full multi-line help text.
function M.render(command, prog)
  local lines = {}
  if command._about then
    table.insert(lines, command._about)
    table.insert(lines, "")
  end
  table.insert(lines, "Usage: " .. M.usage(command, prog))

  if #command._subcommand_order > 0 then
    table.insert(lines, "")
    table.insert(lines, "Commands:")
    for _, name in ipairs(command._subcommand_order) do
      local sub = command._subcommands[name]
      table.insert(lines, "  " .. name .. (sub._about and ("  " .. sub._about) or ""))
    end
  end

  local positionals, options = split_args(command)
  if #positionals > 0 then
    table.insert(lines, "")
    table.insert(lines, "Arguments:")
    for _, arg in ipairs(positionals) do
      table.insert(lines, "  " .. positional_token(arg) .. (arg._help and ("  " .. arg._help) or ""))
    end
  end
  if #options > 0 then
    table.insert(lines, "")
    table.insert(lines, "Options:")
    for _, arg in ipairs(options) do
      table.insert(lines, "  " .. option_label(arg) .. (arg._help and ("  " .. arg._help) or ""))
    end
  end
  return table.concat(lines, "\n")
end

return M
