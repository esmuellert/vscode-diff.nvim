-- tests/framework/assert.lua
--
-- Assertion library that mirrors the subset of luassert used across the spec files.
--
-- Design: this module returns a callable table. Assigning it to `_G.assert`
-- keeps stdlib behavior intact (`assert(cond)` / `assert(cond, msg)` / passthrough
-- of extra return values from expressions like `assert(fn())`) via `__call`, while
-- exposing the rich `.equals`, `.is_true`, `.are.same`, `.has_no.errors`, etc.
-- helpers used by the specs.

local M = {}

-- ---------------------------------------------------------------------------
-- Formatting helpers
-- ---------------------------------------------------------------------------

local function fmt(v)
  local ok, s = pcall(vim.inspect, v)
  if ok then return s end
  return tostring(v)
end

local function fail(msg, level)
  error(msg, (level or 2) + 1)
end

-- ---------------------------------------------------------------------------
-- Deep equality (delegates to vim.deep_equal, which handles nested tables,
-- mixed keys and cycles).
-- ---------------------------------------------------------------------------

local function deep_equal(a, b)
  if a == b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return false end
  return vim.deep_equal(a, b)
end

-- Strict equality follows luassert's `assert.equal`: for tables this is
-- reference identity, for primitives it degenerates to `==`. This distinction
-- matters: several specs rely on `assert.are_not.equal` to check that two
-- table results are separate copies even when their content is identical
-- (e.g. LRU cache tests).
local function strict_equal(a, b)
  return a == b
end

-- ---------------------------------------------------------------------------
-- Core assertion helpers
-- ---------------------------------------------------------------------------

function M.equals(expected, actual, msg)
  if not strict_equal(expected, actual) then
    fail(string.format(
      "%s\nExpected: %s\nActual:   %s",
      msg or "Values are not equal",
      fmt(expected),
      fmt(actual)
    ), 2)
  end
end
M.equal = M.equals

function M.same(expected, actual, msg)
  if not deep_equal(expected, actual) then
    fail(string.format(
      "%s\nExpected: %s\nActual:   %s",
      msg or "Values are not the same",
      fmt(expected),
      fmt(actual)
    ), 2)
  end
end

function M.not_equal(a, b, msg)
  if strict_equal(a, b) then
    fail(string.format(
      "%s\nExpected values to differ, both were:\n  %s",
      msg or "Values are equal but should differ",
      fmt(a)
    ), 2)
  end
end

function M.not_same(a, b, msg)
  if deep_equal(a, b) then
    fail(string.format(
      "%s\nExpected values to differ, both were:\n  %s",
      msg or "Values are the same but should differ",
      fmt(a)
    ), 2)
  end
end

function M.is_true(v, msg)
  if v ~= true then
    fail(string.format(
      "%s\nExpected: true\nActual:   %s",
      msg or "Expected value to be true",
      fmt(v)
    ), 2)
  end
end

function M.is_false(v, msg)
  if v ~= false then
    fail(string.format(
      "%s\nExpected: false\nActual:   %s",
      msg or "Expected value to be false",
      fmt(v)
    ), 2)
  end
end

function M.is_nil(v, msg)
  if v ~= nil then
    fail(string.format(
      "%s\nExpected: nil\nActual:   %s",
      msg or "Expected value to be nil",
      fmt(v)
    ), 2)
  end
end

function M.is_not_nil(v, msg)
  if v == nil then
    fail(msg or "Expected value to be non-nil, got nil", 2)
  end
end

function M.is_truthy(v, msg)
  if not v then
    fail(string.format(
      "%s\nExpected truthy value, got: %s",
      msg or "Expected value to be truthy",
      fmt(v)
    ), 2)
  end
end

function M.is_falsy(v, msg)
  if v then
    fail(string.format(
      "%s\nExpected falsy value, got: %s",
      msg or "Expected value to be falsy",
      fmt(v)
    ), 2)
  end
end

local function type_check(expected_type)
  return function(v, msg)
    if type(v) ~= expected_type then
      fail(string.format(
        "%s\nExpected type: %s\nActual type:   %s\nValue: %s",
        msg or ("Expected value to be a " .. expected_type),
        expected_type,
        type(v),
        fmt(v)
      ), 2)
    end
  end
end

M.is_function = type_check("function")
M.is_table = type_check("table")
M.is_number = type_check("number")
M.is_string = type_check("string")
M.is_boolean = type_check("boolean")

function M.matches(pattern, s, msg)
  if type(s) ~= "string" or not s:find(pattern) then
    fail(string.format(
      "%s\nExpected string matching: %s\nActual: %s",
      msg or "Value does not match pattern",
      fmt(pattern),
      fmt(s)
    ), 2)
  end
end

function M.has_no_errors(fn, msg)
  local ok, err = pcall(fn)
  if not ok then
    fail(string.format(
      "%s\nExpected no error, got: %s",
      msg or "Function raised an error",
      tostring(err)
    ), 2)
  end
end

function M.has_error(fn, expected, msg)
  local ok, err = pcall(fn)
  if ok then
    fail(msg or "Expected function to raise an error, but it did not", 2)
  end
  if expected ~= nil and not deep_equal(expected, err) then
    if type(expected) ~= "string" or type(err) ~= "string" or not err:find(expected, 1, true) then
      fail(string.format(
        "%s\nExpected error: %s\nActual error:  %s",
        msg or "Error did not match expected",
        fmt(expected),
        fmt(err)
      ), 2)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Chainable sub-tables (`assert.are.equal`, `assert.is_not.equal`, etc.)
-- ---------------------------------------------------------------------------

M.are = {
  equal = M.equals,
  equals = M.equals,
  same = M.same,
}

M.are_not = {
  equal = M.not_equal,
  equals = M.not_equal,
  same = M.not_same,
}

M.is_not = {
  equal = M.not_equal,
  equals = M.not_equal,
  same = M.not_same,
  ["nil"] = M.is_not_nil,
}

M.is = {
  equal = M.equals,
  equals = M.equals,
  same = M.same,
  truthy = M.is_truthy,
  falsy = M.is_falsy,
  ["true"] = M.is_true,
  ["false"] = M.is_false,
  ["nil"] = M.is_nil,
}

M.has_no = {
  errors = M.has_no_errors,
  error = M.has_no_errors,
}

M.has = {
  errors = M.has_error,
  error = M.has_error,
  no = M.has_no,
}

-- ---------------------------------------------------------------------------
-- Callable table: keeps stdlib `assert(cond[, msg, ...])` behavior and passes
-- through all return values (needed for patterns like `local m = assert(fn())`).
-- ---------------------------------------------------------------------------

return setmetatable(M, {
  __call = function(_, v, ...)
    if not v then
      local msg = ...
      error(msg or "assertion failed!", 2)
    end
    return v, ...
  end,
})
