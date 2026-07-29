-- tests/framework/reporter.lua
--
-- Stdout reporter used by tests/framework/runner.lua. Prints one line per test
-- (with color prefix), a failure block with traceback when tests fail, and a
-- summary line per spec file.

local M = {}

-- ---------------------------------------------------------------------------
-- Colors
-- ---------------------------------------------------------------------------

local function tty_supports_color()
  if vim.env.NO_COLOR and vim.env.NO_COLOR ~= "" then return false end
  if vim.env.CODEDIFF_TEST_NO_COLOR and vim.env.CODEDIFF_TEST_NO_COLOR ~= "" then return false end
  -- CI environments (GitHub Actions) render ANSI colors in logs.
  return true
end

local use_color = tty_supports_color()
local function color(s, code)
  if not use_color then return s end
  return "\27[" .. code .. "m" .. s .. "\27[0m"
end

local function red(s) return color(s, "31") end
local function green(s) return color(s, "32") end
local function yellow(s) return color(s, "33") end
local function cyan(s) return color(s, "36") end
local function dim(s) return color(s, "2") end

-- ---------------------------------------------------------------------------
-- Output primitives
-- ---------------------------------------------------------------------------

local function write(line)
  -- Use io.write + "\n" so output is line-buffered and shows up in `nvim
  -- --headless` runs immediately (Neovim's `print` also works, but io.write
  -- integrates better with shell pipes on Windows).
  io.write(line, "\n")
end

local function indent(prefix, block)
  local out = {}
  for line in tostring(block):gmatch("([^\n]*)\n?") do
    if line ~= "" then table.insert(out, prefix .. line) end
  end
  return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function M.print_header(spec_file)
  write(cyan("┌─ " .. spec_file))
end

--- Print one test's result.
-- @param names table describe-name chain (outermost first, may be empty)
-- @param test_name string
-- @param status "pass" | "fail" | "pending"
-- @param message string|nil  (failure traceback or pending reason)
-- @param duration_ms number|nil
function M.print_test(names, test_name, status, message, duration_ms)
  local prefix
  if status == "pass" then
    prefix = green("  ✓")
  elseif status == "fail" then
    prefix = red("  ✗")
  else
    prefix = yellow("  -")
  end

  local desc_str = ""
  if #names > 0 then
    desc_str = dim(table.concat(names, " › ") .. " › ")
  end

  local dur = ""
  if status == "pass" and duration_ms and duration_ms > 0 then
    dur = " " .. dim("(" .. duration_ms .. "ms)")
  end

  write(prefix .. " " .. desc_str .. test_name .. dur)

  if message and message ~= "" then
    write(indent("      " .. (status == "fail" and red("│ ") or yellow("│ ")), message))
  end
end

function M.print_summary(spec_file, pass, fail, pending, total_ms)
  local parts = {}
  table.insert(parts, green(pass .. " passed"))
  if fail > 0 then
    table.insert(parts, red(fail .. " failed"))
  else
    table.insert(parts, fail .. " failed")
  end
  if pending > 0 then
    table.insert(parts, yellow(pending .. " pending"))
  else
    table.insert(parts, pending .. " pending")
  end

  local prefix
  if fail > 0 then
    prefix = red("└─ FAIL ")
  elseif pass == 0 and pending == 0 then
    prefix = yellow("└─ EMPTY ")
  else
    prefix = green("└─ OK ")
  end

  write(prefix .. spec_file .. "  " .. table.concat(parts, ", ") .. dim("  (" .. total_ms .. "ms)"))
end

function M.print_load_error(spec_file, err)
  write(red("┌─ LOAD ERROR ") .. spec_file)
  write(indent("  " .. red("│ "), err))
  write(red("└─ FAIL ") .. spec_file)
end

return M
