-- tests/framework/busted.lua
--
-- Minimal busted-compatible test collector. Installs the `describe`, `it`,
-- `before_each`, `after_each` and `pending` globals. Test execution is handled
-- by tests/framework/runner.lua.

local M = {}

-- Sentinel error raised by `pending()` inside a running test to unwind the
-- stack cleanly. The runner treats a test with `state.pending == true` as
-- pending regardless of whether the sentinel is what surfaced from xpcall.
local PENDING_SENTINEL = {}
M.PENDING_SENTINEL = PENDING_SENTINEL

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local root, current, all_tests
local runtime_state

local function make_group(name, parent)
  return {
    name = name,
    parent = parent,
    before_each = {},
    after_each = {},
    tests = {},
    children = {},
  }
end

local function reset()
  root = make_group("", nil)
  current = root
  all_tests = {}
  runtime_state = { current_test = nil }
end

reset()

M.reset = reset

-- ---------------------------------------------------------------------------
-- Test/group registration
-- ---------------------------------------------------------------------------

local function add_test(name, fn, opts)
  opts = opts or {}
  local test = {
    name = name,
    fn = fn,
    group = current,
    pending = opts.pending or false,
    pending_msg = opts.pending_msg,
  }
  table.insert(current.tests, test)
  table.insert(all_tests, test)
  return test
end

local function do_describe(name, fn)
  local group = make_group(name, current)
  table.insert(current.children, group)
  local prev = current
  current = group
  local ok, err = xpcall(fn, function(e)
    return debug.traceback(tostring(e), 2)
  end)
  current = prev
  if not ok then
    -- describe body itself raised — surface it as a failing pseudo-test so the
    -- runner reports it rather than dying silently during collection.
    add_test("<describe error: " .. name .. ">", function()
      error(err, 0)
    end)
  end
end

local function do_it(name, fn)
  return add_test(name, fn)
end

local function do_pending(name_or_msg, fn)
  if fn then
    -- describe-level pending placeholder: `pending("name", function() ... end)`
    return add_test(name_or_msg or "pending", fn, { pending = true, pending_msg = name_or_msg })
  end

  if runtime_state.current_test then
    -- Called mid-test: mark the running test pending and unwind via sentinel.
    runtime_state.current_test.pending = true
    runtime_state.current_test.pending_msg = name_or_msg
    error(PENDING_SENTINEL, 2)
  end

  -- Called at describe body level with no fn: create a body-less pending entry.
  return add_test(name_or_msg or "pending", nil, { pending = true, pending_msg = name_or_msg })
end

-- ---------------------------------------------------------------------------
-- Installation of globals
-- ---------------------------------------------------------------------------

local installed = false

function M.install()
  if installed then return end
  installed = true

  _G.describe = do_describe
  _G.it = do_it
  _G.pending = do_pending

  _G.before_each = function(fn)
    table.insert(current.before_each, fn)
  end

  _G.after_each = function(fn)
    table.insert(current.after_each, fn)
  end
end

-- ---------------------------------------------------------------------------
-- Query API used by the runner
-- ---------------------------------------------------------------------------

function M.get_tests()
  return all_tests
end

--- Return the ordered describe-block names from root down to the test.
function M.describe_chain(test)
  local names = {}
  local node = test.group
  while node and node.parent do
    table.insert(names, 1, node.name)
    node = node.parent
  end
  return names
end

--- Return the flat list of hooks that should run for a test.
-- @param test any
-- @param kind "before_each" or "after_each"
-- Ordering:
--   before_each: outer -> inner (root's first, test's group last)
--   after_each:  inner -> outer (test's group first, root's last)
function M.hooks_for(test, kind)
  local chain = {}
  local node = test.group
  while node do
    table.insert(chain, 1, node) -- prepend so root ends up first
    node = node.parent
  end

  local hooks = {}
  if kind == "before_each" then
    for _, group in ipairs(chain) do
      for _, h in ipairs(group.before_each) do
        table.insert(hooks, h)
      end
    end
  else -- after_each
    for i = #chain, 1, -1 do
      local group = chain[i]
      for _, h in ipairs(group.after_each) do
        table.insert(hooks, h)
      end
    end
  end
  return hooks
end

--- Runtime state accessor used by the runner to mark the currently executing test.
function M.set_current(test)
  runtime_state.current_test = test
end

function M.get_current()
  return runtime_state.current_test
end

return M
