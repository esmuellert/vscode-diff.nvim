-- The parse pipeline. Pure (no vim.* calls): (command, tokens) -> Matches | Error.
-- Mirrors clap's parser: tokenize -> identify long/short/positional/subcommand
-- -> ValueParser -> ArgAction -> validate (required/conflicts/requires) -> Matches.
local action = require("codediff.core.argparse.action")
local errors = require("codediff.core.argparse.error")
local Matches = require("codediff.core.argparse.matches")

local M = {}

-- Classify a single token.
-- Returns kind, name, inline_value where kind is:
--   "endopts" for "--", "long"/"short" for flags, or nil for a positional.
local function classify(tok)
  if tok == "--" then
    return "endopts"
  end
  local long, val = tok:match("^%-%-([^=]+)=(.*)$")
  if long then
    return "long", long, val
  end
  long = tok:match("^%-%-([^=]+)$")
  if long then
    return "long", long, nil
  end
  -- Short: -x, -x=value, -xvalue. A lone "-" is treated as positional.
  local sname, sval = tok:match("^%-([^%-=])=(.*)$")
  if sname then
    return "short", sname, sval
  end
  sname = tok:match("^%-([^%-])(.*)$")
  if sname then
    local rest = tok:sub(3)
    if rest == "" then
      return "short", sname, nil
    end
    return "short", sname, rest
  end
  return nil
end

-- Build the flag lookup and positional list for a command, merging inherited
-- global args from ancestors.
local function index_args(command, inherited)
  local by_name = {} -- "--long"/"-s" -> { arg, is_global }
  local positionals = {}
  local own_globals = {}
  local function register(arg, is_global)
    if arg._long then
      by_name["--" .. arg._long] = { arg = arg, is_global = is_global }
    end
    if arg._short then
      by_name["-" .. arg._short] = { arg = arg, is_global = is_global }
    end
  end
  for _, arg in ipairs(command._args) do
    if arg:is_positional() then
      table.insert(positionals, arg)
    else
      register(arg, arg._global)
      if arg._global then
        table.insert(own_globals, arg)
      end
    end
  end
  for _, arg in ipairs(inherited) do
    register(arg, true)
  end
  return by_name, positionals, own_globals
end

local function apply_flag(arg, key, raw, target)
  if arg:takes_value() then
    local val, detail = arg._value_parser.parse(raw)
    if detail then
      return errors.invalid_value(key, detail)
    end
    if arg._action == action.APPEND then
      local list = target[arg.id] or {}
      table.insert(list, val)
      target[arg.id] = list
    else
      target[arg.id] = val
    end
  else
    if arg._action == action.SET_TRUE then
      target[arg.id] = true
    elseif arg._action == action.SET_FALSE then
      target[arg.id] = false
    elseif arg._action == action.COUNT then
      target[arg.id] = (target[arg.id] or 0) + 1
    end
  end
  return nil
end

-- Assign collected positional tokens to the command's positional args in order.
-- An APPEND positional consumes all remaining tokens (variadic).
local function assign_positionals(positionals, pos_tokens, local_values, seen)
  local idx = 1
  for _, parg in ipairs(positionals) do
    if parg._action == action.APPEND then
      local list = {}
      while idx <= #pos_tokens do
        local val, detail = parg._value_parser.parse(pos_tokens[idx])
        if detail then
          return errors.invalid_value(parg:display_name(), detail)
        end
        table.insert(list, val)
        idx = idx + 1
      end
      if #list > 0 then
        local_values[parg.id] = list
        seen[parg.id] = true
      end
    elseif idx <= #pos_tokens then
      local val, detail = parg._value_parser.parse(pos_tokens[idx])
      if detail then
        return errors.invalid_value(parg:display_name(), detail)
      end
      local_values[parg.id] = val
      seen[parg.id] = true
      idx = idx + 1
    end
  end
  if idx <= #pos_tokens then
    return errors.too_many_arguments(pos_tokens[idx])
  end
  return nil
end

-- Apply defaults, then validate required / conflicts / requires.
local function finalize(command, local_values, global_values, seen)
  for _, arg in ipairs(command._args) do
    local target = arg._global and global_values or local_values
    if target[arg.id] == nil and arg._default ~= nil then
      target[arg.id] = arg._default
    end
  end
  for _, arg in ipairs(command._args) do
    local target = arg._global and global_values or local_values
    if arg._required and target[arg.id] == nil then
      return errors.missing_required(arg:display_name())
    end
  end
  local function was_seen(id)
    return seen[id] == true or global_values[id] ~= nil
  end
  for _, arg in ipairs(command._args) do
    if was_seen(arg.id) then
      for _, other in ipairs(arg._conflicts) do
        if was_seen(other) then
          return errors.conflict(arg.id, other)
        end
      end
      for _, other in ipairs(arg._requires) do
        if not was_seen(other) then
          return errors.missing_requirement(arg.id, other)
        end
      end
    end
  end
  return nil
end

-- opts = { global_values, inherited_globals, bang, range }
function M.parse(command, tokens, opts)
  opts = opts or {}
  local global_values = opts.global_values or {}
  local inherited = opts.inherited_globals or {}

  local by_name, positionals, own_globals = index_args(command, inherited)

  local local_values = {}
  local pos_tokens = {}
  local seen = {}
  local sub_result = nil
  local end_of_opts = false

  local i, n = 1, #tokens
  while i <= n do
    local tok = tokens[i]
    if end_of_opts then
      table.insert(pos_tokens, tok)
      i = i + 1
    else
      local kind, name, inline = classify(tok)
      if kind == "endopts" then
        end_of_opts = true
        i = i + 1
      elseif kind == "long" or kind == "short" then
        local key = (kind == "long" and "--" or "-") .. name
        local entry = by_name[key]
        if not entry then
          return nil, errors.unknown_argument(key)
        end
        local arg = entry.arg
        local raw = inline
        if arg:takes_value() and raw == nil then
          i = i + 1
          if i > n then
            return nil, errors.missing_value(key)
          end
          raw = tokens[i]
        elseif not arg:takes_value() and inline ~= nil then
          return nil, errors.invalid_value(key, "flag does not take a value")
        end
        local target = entry.is_global and global_values or local_values
        local aerr = apply_flag(arg, key, raw, target)
        if aerr then
          return nil, aerr
        end
        seen[arg.id] = true
        i = i + 1
      elseif #pos_tokens == 0 and command._subcommands[tok] then
        local child = command._subcommands[tok]
        local child_inherited = {}
        for _, a in ipairs(inherited) do
          table.insert(child_inherited, a)
        end
        for _, a in ipairs(own_globals) do
          table.insert(child_inherited, a)
        end
        local rest = {}
        for j = i + 1, n do
          table.insert(rest, tokens[j])
        end
        local sm, serr = M.parse(child, rest, {
          global_values = global_values,
          inherited_globals = child_inherited,
          bang = opts.bang,
          range = opts.range,
        })
        if serr then
          return nil, serr
        end
        sub_result = { name = tok, matches = sm }
        i = n + 1
      else
        table.insert(pos_tokens, tok)
        i = i + 1
      end
    end
  end

  if not sub_result then
    local perr = assign_positionals(positionals, pos_tokens, local_values, seen)
    if perr then
      return nil, perr
    end
  end

  local ferr = finalize(command, local_values, global_values, seen)
  if ferr then
    return nil, ferr
  end

  return Matches.new({
    values = local_values,
    globals = global_values,
    subcommand = sub_result,
    bang = opts.bang,
    range = opts.range,
  }), nil
end

return M
