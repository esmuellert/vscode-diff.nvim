-- Command: a (sub)command in the CLI tree. Mirrors clap's Command. Holds args,
-- nested subcommands, and (our cobra-style addition) an optional handler so the
-- app can dispatch straight to the matched leaf command.
local parser = require("codediff.core.argparse.parser")

local Command = {}
Command.__index = Command

function Command.new(name)
  return setmetatable({
    _name = name,
    _about = nil,
    _args = {},
    _subcommands = {},
    _subcommand_order = {},
    _handler = nil,
  }, Command)
end

function Command:about(text)
  self._about = text
  return self
end

function Command:arg(a)
  table.insert(self._args, a)
  return self
end

function Command:args(list)
  for _, a in ipairs(list) do
    table.insert(self._args, a)
  end
  return self
end

function Command:subcommand(cmd)
  self._subcommands[cmd._name] = cmd
  table.insert(self._subcommand_order, cmd._name)
  return self
end

-- Handler invoked for this command when it is the matched leaf (cobra-style).
function Command:handler(fn)
  self._handler = fn
  return self
end

-- Ordered list of subcommand Commands (for help/completion).
function Command:subcommands()
  local list = {}
  for _, name in ipairs(self._subcommand_order) do
    table.insert(list, self._subcommands[name])
  end
  return list
end

-- Parse tokens into ArgMatches. ctx = { bang, range } (Neovim command extras).
-- Returns matches | (nil, Error).
function Command:parse(tokens, ctx)
  return parser.parse(self, tokens, {
    bang = ctx and ctx.bang,
    range = ctx and ctx.range,
  })
end

-- Parse and dispatch to the matched leaf command's handler.
-- Returns matches | (nil, Error). Parsing errors are returned, never thrown,
-- so the caller can route them to vim.notify.
function Command:execute(tokens, ctx)
  local matches, err = self:parse(tokens, ctx)
  if err then
    return nil, err
  end

  local cmd, leaf = self, matches
  while true do
    local name, sub = leaf:subcommand()
    if not name then
      break
    end
    cmd = cmd._subcommands[name]
    leaf = sub
  end

  if cmd._handler then
    cmd._handler(leaf)
  end
  return matches, nil
end

return Command
