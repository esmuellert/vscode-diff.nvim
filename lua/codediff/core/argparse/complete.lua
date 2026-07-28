-- Completion candidate generation from a Command tree, for a Neovim `:command`
-- complete callback. clap generates shell-completion scripts; a Neovim command
-- instead needs live candidate lists, including dynamic values (git refs,
-- files) provided per-arg via :completor().
--
--   M.complete(command, prior_tokens, arg_lead) -> { candidate, ... }
--
-- `prior_tokens` are the already-typed tokens (excluding the command name and
-- the partial `arg_lead` currently being completed).
local action = require("codediff.core.argparse.action")

local M = {}

-- Flag lookup ("--long"/"-s" -> Arg) for a command plus inherited globals.
local function index_flags(command, inherited)
  local by_name = {}
  local order = {}
  local function add(arg)
    if arg._long then
      local k = "--" .. arg._long
      if not by_name[k] then
        table.insert(order, k)
      end
      by_name[k] = arg
    end
    if arg._short then
      local k = "-" .. arg._short
      if not by_name[k] then
        table.insert(order, k)
      end
      by_name[k] = arg
    end
  end
  for _, arg in ipairs(command._args) do
    if not arg:is_positional() then
      add(arg)
    end
  end
  for _, arg in ipairs(inherited) do
    add(arg)
  end
  return by_name, order
end

-- Is this token a flag? Returns "--long"/"-s" key and whether it had an inline
-- value (=...); returns nil for positionals.
local function flag_key(tok)
  local long = tok:match("^(%-%-[^=]+)=")
  if long then
    return long, true
  end
  if tok:match("^%-%-[^=]+$") then
    return tok, false
  end
  local short = tok:match("^(%-[^%-=])=")
  if short then
    return short, true
  end
  if tok:match("^%-[^%-]") then
    return tok:sub(1, 2), (#tok > 2)
  end
  return nil
end

-- Walk the already-typed tokens to find the active command, inherited globals,
-- used flags, positional count, and any option awaiting its value (`pending`).
local function resolve_context(command, prior)
  local cmd = command
  local inherited = {}
  local used = {}
  local positional_count = 0
  local pending = nil
  local end_of_opts = false

  local i = 1
  while i <= #prior do
    local tok = prior[i]
    pending = nil
    if end_of_opts then
      positional_count = positional_count + 1
      i = i + 1
    elseif tok == "--" then
      end_of_opts = true
      i = i + 1
    else
      local by_name = index_flags(cmd, inherited)
      local key, has_inline = flag_key(tok)
      if key then
        local arg = by_name[key]
        if arg then
          used[arg.id] = true
          if arg:takes_value() and not has_inline then
            if i == #prior then
              pending = arg
              i = i + 1
            else
              i = i + 2 -- skip the option and its value token
            end
          else
            i = i + 1
          end
        else
          i = i + 1 -- unknown flag; ignore for context
        end
      elseif positional_count == 0 and cmd._subcommands[tok] then
        for _, a in ipairs(cmd._args) do
          if a._global then
            table.insert(inherited, a)
          end
        end
        cmd = cmd._subcommands[tok]
        i = i + 1
      else
        positional_count = positional_count + 1
        i = i + 1
      end
    end
  end

  return {
    command = cmd,
    inherited = inherited,
    used = used,
    positional_count = positional_count,
    pending = pending,
    end_of_opts = end_of_opts,
  }
end

local function value_candidates(arg, arg_lead, cmd)
  local out = {}
  if arg._value_parser and arg._value_parser.choices then
    for _, ch in ipairs(arg._value_parser.choices) do
      table.insert(out, ch)
    end
  elseif arg._completor then
    for _, ch in ipairs(arg._completor({ arg_lead = arg_lead, command = cmd }) or {}) do
      table.insert(out, ch)
    end
  end
  return out
end

local function positional_at(command, index)
  local positionals = {}
  for _, arg in ipairs(command._args) do
    if arg:is_positional() then
      table.insert(positionals, arg)
    end
  end
  local parg = positionals[index]
  if parg then
    return parg
  end
  -- A trailing variadic positional keeps matching past its index.
  local last = positionals[#positionals]
  if last and last._action == action.APPEND then
    return last
  end
  return nil
end

function M.complete(command, prior, arg_lead)
  prior = prior or {}
  arg_lead = arg_lead or ""
  local ctx = resolve_context(command, prior)
  local cmd = ctx.command

  local out = {}
  local function add(cand)
    if cand:find(arg_lead, 1, true) == 1 then
      table.insert(out, cand)
    end
  end

  -- Completing the value of an option (e.g. `--base <lead>`).
  if ctx.pending then
    for _, ch in ipairs(value_candidates(ctx.pending, arg_lead, cmd)) do
      add(ch)
    end
    return out
  end

  -- After `--`: complete trailing operands (e.g. git pathspecs) via the
  -- command's trailing completor. Never offer flags/subcommands/positionals here.
  if ctx.end_of_opts then
    if cmd._trailing then
      for _, ch in ipairs(value_candidates(cmd._trailing, arg_lead, cmd)) do
        add(ch)
      end
    end
    return out
  end

  -- Completing a flag name.
  if arg_lead:sub(1, 1) == "-" then
    local by_name, order = index_flags(cmd, ctx.inherited)
    for _, key in ipairs(order) do
      local arg = by_name[key]
      local repeatable = arg._action == action.APPEND or arg._action == action.COUNT
      if repeatable or not ctx.used[arg.id] then
        add(key)
      end
    end
    return out
  end

  -- Positional context: offer subcommands at the first slot, plus the current
  -- positional's dynamic candidates.
  if ctx.positional_count == 0 and #cmd._subcommand_order > 0 then
    for _, name in ipairs(cmd._subcommand_order) do
      add(name)
    end
  end
  local parg = positional_at(cmd, ctx.positional_count + 1)
  if parg then
    for _, ch in ipairs(value_candidates(parg, arg_lead, cmd)) do
      add(ch)
    end
  end
  return out
end

return M
