-- Arg: one command-line argument (option, flag, or positional). Mirrors clap's
-- Arg. An argument is positional when it has neither a long nor a short name.
-- Built with method chaining; each setter returns self.
local action = require("codediff.core.argparse.action")
local value_parser = require("codediff.core.argparse.value_parser")

local Arg = {}
Arg.__index = Arg

-- Strip any leading dashes so callers may pass "--name", "-n", or bare names.
local function strip_dashes(name)
  return (name:gsub("^%-+", ""))
end

function Arg.new(id)
  assert(type(id) == "string" and id ~= "", "Arg.new requires a non-empty id")
  return setmetatable({
    id = id,
    _long = nil,
    _short = nil,
    _help = nil,
    _value_name = nil,
    _action = action.SET,
    _value_parser = value_parser.string,
    _default = nil,
    _required = false,
    _conflicts = {},
    _requires = {},
    _completor = nil,
    _global = false,
  }, Arg)
end

-- Convenience: a boolean flag (SET_TRUE, takes no value).
function Arg.flag(id)
  return Arg.new(id):action(action.SET_TRUE)
end

-- Convenience: an explicit positional (no long/short).
function Arg.positional(id)
  return Arg.new(id)
end

function Arg:long(name)
  self._long = strip_dashes(name)
  return self
end

function Arg:short(name)
  self._short = strip_dashes(name)
  return self
end

function Arg:help(text)
  self._help = text
  return self
end

function Arg:value_name(name)
  self._value_name = name
  return self
end

function Arg:action(a)
  self._action = a
  return self
end

function Arg:value_parser(vp)
  self._value_parser = vp
  return self
end

function Arg:default(v)
  self._default = v
  return self
end

function Arg:required(v)
  self._required = (v ~= false)
  return self
end

-- Shortcut: constrain to a fixed set (sets an enum value_parser).
function Arg:choices(list)
  self._value_parser = value_parser.enum(list)
  return self
end

function Arg:conflicts_with(other)
  if type(other) == "table" then
    for _, o in ipairs(other) do
      table.insert(self._conflicts, o)
    end
  else
    table.insert(self._conflicts, other)
  end
  return self
end

function Arg:requires(other)
  if type(other) == "table" then
    for _, o in ipairs(other) do
      table.insert(self._requires, o)
    end
  else
    table.insert(self._requires, other)
  end
  return self
end

-- Dynamic value completion hook: fn(ctx) -> { candidate, ... }.
function Arg:completor(fn)
  self._completor = fn
  return self
end

-- Persistent/global: recognized by this command and all descendants.
function Arg:global(v)
  self._global = (v ~= false)
  return self
end

function Arg:is_positional()
  return self._long == nil and self._short == nil
end

function Arg:takes_value()
  return action.takes_value(self._action)
end

-- Human-readable name for help/error messages.
function Arg:display_name()
  if self._long then
    return "--" .. self._long
  end
  if self._short then
    return "-" .. self._short
  end
  return "<" .. self.id .. ">"
end

return Arg
