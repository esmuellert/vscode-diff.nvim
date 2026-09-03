-- Combines both sides of one conflict block.
local M = {}

--- Try to smart combine inputs like VSCode does
--- This interleaves character-level edits sorted by their position in base
--- Returns nil if edits overlap and cannot be combined
--- @param session table Session with buffer references
--- @param block table Conflict block with inner1, inner2
--- @param first_input number 1 or 2 - which input takes priority on ties
--- @return table|nil Combined lines, or nil if cannot be combined
function M.smart_combine_inputs(session, block, first_input)
  local inner1 = block.inner1 or {}
  local inner2 = block.inner2 or {}

  -- If either side has no inner changes, we can't do smart combination
  -- (means entire block was replaced, not fine-grained edits)
  if #inner1 == 0 or #inner2 == 0 then
    return nil
  end

  -- Collect all range edits with their source
  -- Each inner has: original (position in base), modified (position in input)
  local combined_edits = {}

  for _, inner in ipairs(inner1) do
    table.insert(combined_edits, {
      input_range = inner.original, -- Range in base file
      output_range = inner.modified, -- Range in input file
      input = 1,
    })
  end
  for _, inner in ipairs(inner2) do
    table.insert(combined_edits, {
      input_range = inner.original,
      output_range = inner.modified,
      input = 2,
    })
  end

  -- Sort by position in base (input_range), with first_input taking priority on ties
  -- This matches VSCode's: compareBy((d) => d.diff.inputRange, Range.compareRangesUsingStarts)
  table.sort(combined_edits, function(a, b)
    local a_start_line = a.input_range.start_line
    local a_start_col = a.input_range.start_col
    local b_start_line = b.input_range.start_line
    local b_start_col = b.input_range.start_col

    if a_start_line ~= b_start_line then
      return a_start_line < b_start_line
    end
    if a_start_col ~= b_start_col then
      return a_start_col < b_start_col
    end
    -- Tie-breaker: first_input comes first (lower number = earlier)
    local a_priority = (a.input == first_input) and 1 or 2
    local b_priority = (b.input == first_input) and 1 or 2
    return a_priority < b_priority
  end)

  -- Get input buffer contents (VSCode uses textModel.getValueInRange on full models).
  -- For the merge base we use session.merge_base_lines (true stage-:1 content)
  -- rather than reading from result_bufnr — the Result buffer is now seeded
  -- with the auto-merged content, so its line numbers no longer match
  -- base_range.
  local base_lines = session.merge_base_lines or session.result_base_lines or {}
  local input1_bufnr = session.original_bufnr
  local input2_bufnr = session.modified_bufnr

  -- Helper: get text from buffer between two positions (like VSCode's getValueInRange)
  -- Positions are 1-based (line, col)
  local function get_value_in_range(bufnr, start_line, start_col, end_line, end_col)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
      return ""
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
    if #lines == 0 then
      return ""
    end

    if #lines == 1 then
      -- Single line: extract from start_col to end_col-1
      local line = lines[1] or ""
      return line:sub(start_col, end_col - 1)
    else
      -- Multi-line: first line from start_col, middle lines full, last line to end_col-1
      local result = {}
      result[1] = (lines[1] or ""):sub(start_col)
      for i = 2, #lines - 1 do
        result[#result + 1] = lines[i] or ""
      end
      result[#result + 1] = (lines[#lines] or ""):sub(1, end_col - 1)
      return table.concat(result, "\n")
    end
  end

  -- Helper: get text from a string array (base_lines) between two 1-based
  -- positions. Mirrors get_value_in_range but for in-memory line tables.
  local function get_value_in_lines(source, start_line, start_col, end_line, end_col)
    if start_line > end_line then
      return ""
    end
    if start_line == end_line then
      return (source[start_line] or ""):sub(start_col, end_col - 1)
    end
    local out = {}
    out[1] = (source[start_line] or ""):sub(start_col)
    for i = start_line + 1, end_line - 1 do
      out[#out + 1] = source[i] or ""
    end
    out[#out + 1] = (source[end_line] or ""):sub(1, end_col - 1)
    return table.concat(out, "\n")
  end

  -- Build result text by walking through base and applying edits
  -- This matches VSCode's editsToLineRangeEdit function
  local base_range = block.base_range
  local result_text = ""

  -- Start position: VSCode starts at end of line before base_range if exists
  local starts_line_before = base_range.start_line > 1
  local current_line, current_col
  if starts_line_before then
    current_line = base_range.start_line - 1
    current_col = #(base_lines[current_line] or "") + 1 -- Position after last char (like getLineMaxColumn)
  else
    current_line = base_range.start_line
    current_col = 1
  end

  for _, edit in ipairs(combined_edits) do
    local diff_start_line = edit.input_range.start_line
    local diff_start_col = edit.input_range.start_col

    -- Check overlap: current position must be <= edit start
    if current_line > diff_start_line or (current_line == diff_start_line and current_col > diff_start_col) then
      return nil -- Overlap detected, cannot combine
    end

    -- Get base text from current position to edit start (read from base_lines,
    -- not from result_bufnr, since the Result buffer no longer mirrors BASE)
    local original_text = get_value_in_lines(base_lines, current_line, current_col, diff_start_line, diff_start_col)

    -- Handle virtual newline if edit starts past end of file
    if diff_start_line > #base_lines then
      original_text = original_text .. "\n"
    end

    result_text = result_text .. original_text

    -- Get replacement text from input
    local source_bufnr = (edit.input == 1) and input1_bufnr or input2_bufnr
    local new_text = get_value_in_range(source_bufnr, edit.output_range.start_line, edit.output_range.start_col, edit.output_range.end_line, edit.output_range.end_col)
    result_text = result_text .. new_text

    -- Move current position to end of edit's input_range
    current_line = edit.input_range.end_line
    current_col = edit.input_range.end_col
  end

  -- Get remaining base text after last edit
  local ends_line_after = base_range.end_line <= #base_lines
  local end_line, end_col
  if ends_line_after then
    end_line = base_range.end_line
    end_col = 1
  else
    end_line = math.max(1, base_range.end_line - 1)
    end_col = #(base_lines[end_line] or "") + 1
  end

  local remaining_text = get_value_in_lines(base_lines, current_line, current_col, end_line, end_col)
  result_text = result_text .. remaining_text

  -- Split result into lines (like VSCode's splitLines)
  local result_lines = {}
  for line in (result_text .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(result_lines, line)
  end
  -- Remove the extra empty line from our gmatch pattern
  if #result_lines > 0 and result_lines[#result_lines] == "" and not result_text:match("\n$") then
    table.remove(result_lines)
  end

  -- Trim leading line if we started before base_range
  if starts_line_before and #result_lines > 0 then
    if result_lines[1] ~= "" then
      return nil -- First line should be empty
    end
    table.remove(result_lines, 1)
  end

  -- Trim trailing line if we end after base_range
  if ends_line_after and #result_lines > 0 then
    if result_lines[#result_lines] ~= "" then
      return nil -- Last line should be empty
    end
    table.remove(result_lines)
  end

  return result_lines
end

--- Dumb combine: just concatenate input1 then input2 (fallback)
--- @param input1_lines table
--- @param input2_lines table
--- @param first_input number 1 or 2
--- @return table Combined lines
function M.dumb_combine_inputs(input1_lines, input2_lines, first_input)
  local combined = {}
  local first_lines = (first_input == 1) and input1_lines or input2_lines
  local second_lines = (first_input == 1) and input2_lines or input1_lines

  for _, line in ipairs(first_lines) do
    table.insert(combined, line)
  end
  for _, line in ipairs(second_lines) do
    table.insert(combined, line)
  end

  return combined
end

return M
