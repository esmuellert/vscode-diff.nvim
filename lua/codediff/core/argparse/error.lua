-- Structured parse errors. Mirrors clap's Error/ErrorKind, adapted for Neovim:
-- there is no process to exit, so parsing returns an Error value that the caller
-- routes to vim.notify. `tostring(err)` yields a user-facing message.
local M = {}

M.KIND = {
  UNKNOWN_ARGUMENT = "unknown_argument",
  MISSING_VALUE = "missing_value",
  INVALID_VALUE = "invalid_value",
  MISSING_REQUIRED = "missing_required",
  TOO_MANY_ARGUMENTS = "too_many_arguments",
  CONFLICT = "conflict",
  MISSING_REQUIREMENT = "missing_requirement",
}

local Error = {}
Error.__index = Error

function Error.__tostring(self)
  return self.message
end

function Error.new(kind, message)
  return setmetatable({ kind = kind, message = message }, Error)
end

M.Error = Error

-- Is a value an Error produced by this module?
function M.is_error(v)
  return getmetatable(v) == Error
end

function M.unknown_argument(name)
  return Error.new(M.KIND.UNKNOWN_ARGUMENT, "unknown argument '" .. name .. "'")
end

function M.missing_value(name)
  return Error.new(M.KIND.MISSING_VALUE, "argument '" .. name .. "' requires a value")
end

function M.invalid_value(name, detail)
  return Error.new(M.KIND.INVALID_VALUE, "invalid value for '" .. name .. "': " .. detail)
end

function M.missing_required(name)
  return Error.new(M.KIND.MISSING_REQUIRED, "missing required argument " .. name)
end

function M.too_many_arguments(token)
  return Error.new(M.KIND.TOO_MANY_ARGUMENTS, "unexpected argument '" .. token .. "'")
end

function M.conflict(a, b)
  return Error.new(M.KIND.CONFLICT, "argument '" .. a .. "' cannot be used with '" .. b .. "'")
end

function M.missing_requirement(a, b)
  return Error.new(M.KIND.MISSING_REQUIREMENT, "argument '" .. a .. "' requires '" .. b .. "'")
end

return M
