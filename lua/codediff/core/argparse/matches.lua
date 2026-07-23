-- ArgMatches: the immutable result of a successful parse. Mirrors clap's
-- ArgMatches typed getters. Global (persistent) values are shared by reference
-- across the whole match chain, so a global flag is visible from any level.
local Matches = {}
Matches.__index = Matches

-- opts = { values, globals, subcommand = { name, matches }, bang, range }
function Matches.new(opts)
  return setmetatable({
    _values = opts.values or {},
    _globals = opts.globals or {},
    _subcommand = opts.subcommand,
    _bang = opts.bang or false,
    _range = opts.range,
  }, Matches)
end

function Matches:_lookup(id)
  local v = self._values[id]
  if v == nil then
    v = self._globals[id]
  end
  return v
end

-- Single value (clap ArgMatches::get_one). Returns nil when absent.
function Matches:get_one(id)
  return self:_lookup(id)
end

-- Boolean flag (clap ArgMatches::get_flag).
function Matches:get_flag(id)
  return self:_lookup(id) == true
end

-- List of values for APPEND args (clap ArgMatches::get_many). Always a table.
function Matches:get_many(id)
  local v = self:_lookup(id)
  if v == nil then
    return {}
  end
  if type(v) == "table" then
    return v
  end
  return { v }
end

-- Occurrence count for COUNT args (clap ArgMatches::get_count).
function Matches:get_count(id)
  local v = self:_lookup(id)
  if type(v) == "number" then
    return v
  end
  return 0
end

-- Whether an argument was present/resolved (including defaults).
function Matches:contains(id)
  return self:_lookup(id) ~= nil
end

-- The chosen subcommand (clap ArgMatches::subcommand): name, sub_matches.
function Matches:subcommand()
  if self._subcommand then
    return self._subcommand.name, self._subcommand.matches
  end
  return nil
end

-- Neovim extras that a shell CLI lacks:
function Matches:bang()
  return self._bang
end

function Matches:range()
  return self._range
end

return Matches
