-- E2E Test Case Runner
-- This script runs a single E2E test case
-- Usage: nvim --headless -c "luafile tests/e2e/run_case.lua" -- left.txt right.txt [-v]

local diff = require("vscode-diff")

-- Parse arguments
local args = vim.v.argv
local left_file = nil
local right_file = nil
local verbose = false

for i, arg in ipairs(args) do
  if arg:match("%.txt$") and not left_file then
    left_file = arg
  elseif arg:match("%.txt$") and not right_file then
    right_file = arg
  elseif arg == "-v" or arg == "--verbose" then
    verbose = true
  end
end

if not left_file or not right_file then
  print("ERROR: Missing file arguments")
  print("Usage: nvim --headless -c \"luafile tests/e2e/run_case.lua\" -- left.txt right.txt [-v]")
  vim.cmd("cq!") -- Exit with error
  return
end

-- Setup
vim.opt.rtp:prepend(".")

if verbose then
  diff.set_verbose(true)
end

-- Read files
local left_lines = vim.fn.readfile(left_file)
local right_lines = vim.fn.readfile(right_file)

print("Left file contents (" .. #left_lines .. " lines):")
for i, line in ipairs(left_lines) do
  print("  " .. i .. ": " .. line)
end

print("\nRight file contents (" .. #right_lines .. " lines):")
for i, line in ipairs(right_lines) do
  print("  " .. i .. ": " .. line)
end

print("\n" .. string.rep("─", 80))
print("COMPUTING DIFF")
print(string.rep("─", 80) .. "\n")

-- Compute diff
local plan = diff.compute_diff(left_lines, right_lines)

if not verbose then
  -- If not verbose, print a summary
  print("Render Plan Summary:")
  print("  Left:  " .. plan.left.line_count .. " lines")
  print("  Right: " .. plan.right.line_count .. " lines")
  print("")
  
  -- Count filler lines
  local left_fillers = 0
  local right_fillers = 0
  for _, meta in ipairs(plan.left.line_metadata) do
    if meta.is_filler then left_fillers = left_fillers + 1 end
  end
  for _, meta in ipairs(plan.right.line_metadata) do
    if meta.is_filler then right_fillers = right_fillers + 1 end
  end
  
  print("  Left filler lines:  " .. left_fillers)
  print("  Right filler lines: " .. right_fillers)
  print("")
  
  -- Count character highlights
  local left_char_hl = 0
  local right_char_hl = 0
  for _, meta in ipairs(plan.left.line_metadata) do
    left_char_hl = left_char_hl + #meta.char_highlights
  end
  for _, meta in ipairs(plan.right.line_metadata) do
    right_char_hl = right_char_hl + #meta.char_highlights
  end
  
  print("  Left char highlights:  " .. left_char_hl)
  print("  Right char highlights: " .. right_char_hl)
end

print("\n✓ Test case completed\n")

vim.cmd("quit!")
