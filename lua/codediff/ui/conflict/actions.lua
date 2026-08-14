-- Conflict resolution actions (accept incoming/current/both, discard)
local M = {}

local lifecycle = require("codediff.ui.lifecycle")
local auto_refresh = require("codediff.ui.auto_refresh")
local tracking = require("codediff.ui.conflict.tracking")
local signs = require("codediff.ui.conflict.signs")

--- Apply text to result buffer at the conflict's range
--- @param result_bufnr number Result buffer
--- @param block table Conflict block with base_range and optional extmark_id
--- @param lines table Lines to insert
--- @param base_lines table Result-buffer seed content (auto-merged result),
---                       used only for the content-search fallback when the
---                       extmark is invalid. Indexed by result_range, falling
---                       back to base_range for legacy paths.
local function apply_to_result(result_bufnr, block, lines, base_lines)
  local start_row, end_row

  -- Method 1: Try using extmarks (robust against edits)
  if block.extmark_id then
    local mark = vim.api.nvim_buf_get_extmark_by_id(result_bufnr, tracking.tracking_ns, block.extmark_id, { details = true })
    if mark and #mark >= 3 then
      start_row = mark[1]
      end_row = mark[3].end_row
    end
  end

  -- Method 2: Fallback to content search or original range
  if not start_row then
    -- The result buffer seed (base_lines here) is the auto-merged Result, so
    -- the slice for this conflict lives at result_range (which equals the
    -- original BASE slice for unresolved conflict regions). Fall back to
    -- base_range for legacy callers that never set result_range.
    local range = block.result_range or block.base_range
    -- For simplicity, we'll re-apply based on content matching
    -- Find the seed slice in the result buffer
    local base_content = {}
    for i = range.start_line, range.end_line - 1 do
      table.insert(base_content, base_lines[i] or "")
    end

    local result_lines = vim.api.nvim_buf_get_lines(result_bufnr, 0, -1, false)

    -- Search for the seed content in result buffer
    local found_start = nil
    for i = 1, #result_lines - #base_content + 1 do
      local match = true
      for j = 1, #base_content do
        if result_lines[i + j - 1] ~= base_content[j] then
          match = false
          break
        end
      end
      if match then
        found_start = i
        break
      end
    end

    if found_start then
      start_row = found_start - 1
      end_row = found_start - 1 + #base_content
    else
      -- Fallback: try to find by approximate position
      start_row = math.min(range.start_line - 1, #result_lines)
      end_row = math.min(range.end_line - 1, #result_lines)
    end
  end

  if start_row and end_row then
    vim.api.nvim_buf_set_lines(result_bufnr, start_row, end_row, false, lines)
  end
end

--- Accept incoming (left/input1) side for the conflict under cursor
--- @param tabpage number
--- @return boolean success
function M.accept_incoming(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  -- Determine which buffer cursor is in and find the conflict
  local current_buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local side = nil

  if current_buf == session.original_bufnr then
    side = "left"
  elseif current_buf == session.modified_bufnr then
    side = "right"
  else
    vim.notify("[codediff] Cursor not in diff buffer", vim.log.levels.WARN)
    return false
  end

  local block = tracking.find_conflict_at_cursor(session, cursor_line, side, false)
  if not block then
    vim.notify("[codediff] No active conflict at cursor position", vim.log.levels.INFO)
    return false
  end

  -- Get incoming (left) content
  local incoming_lines = tracking.get_lines_for_range(session.original_bufnr, block.output1_range.start_line, block.output1_range.end_line)

  -- Apply to result
  local result_bufnr = session.result_bufnr
  local base_lines = session.result_base_lines
  if not result_bufnr or not base_lines then
    vim.notify("[codediff] No result buffer or base lines", vim.log.levels.ERROR)
    return false
  end

  apply_to_result(result_bufnr, block, incoming_lines, base_lines)
  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  return true
end

--- Accept current (right/input2) side for the conflict under cursor
--- @param tabpage number
--- @return boolean success
function M.accept_current(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local side = nil

  if current_buf == session.original_bufnr then
    side = "left"
  elseif current_buf == session.modified_bufnr then
    side = "right"
  else
    vim.notify("[codediff] Cursor not in diff buffer", vim.log.levels.WARN)
    return false
  end

  local block = tracking.find_conflict_at_cursor(session, cursor_line, side, false)
  if not block then
    vim.notify("[codediff] No active conflict at cursor position", vim.log.levels.INFO)
    return false
  end

  -- Get current (right) content
  local current_lines = tracking.get_lines_for_range(session.modified_bufnr, block.output2_range.start_line, block.output2_range.end_line)

  local result_bufnr = session.result_bufnr
  local base_lines = session.result_base_lines
  if not result_bufnr or not base_lines then
    vim.notify("[codediff] No result buffer or base lines", vim.log.levels.ERROR)
    return false
  end

  apply_to_result(result_bufnr, block, current_lines, base_lines)
  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  return true
end

--- Try to smart combine inputs like VSCode does
--- This interleaves character-level edits sorted by their position in base
--- Returns nil if edits overlap and cannot be combined
--- @param session table Session with buffer references
--- @param block table Conflict block with inner1, inner2
--- @param first_input number 1 or 2 - which input takes priority on ties
--- @return table|nil Combined lines, or nil if cannot be combined
local function smart_combine_inputs(session, block, first_input)
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
local function dumb_combine_inputs(input1_lines, input2_lines, first_input)
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

--- Accept both sides (smart combination like VSCode) for the conflict under cursor
--- @param tabpage number
--- @return boolean success
function M.accept_both(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local side = nil

  if current_buf == session.original_bufnr then
    side = "left"
  elseif current_buf == session.modified_bufnr then
    side = "right"
  else
    vim.notify("[codediff] Cursor not in diff buffer", vim.log.levels.WARN)
    return false
  end

  local block = tracking.find_conflict_at_cursor(session, cursor_line, side, false)
  if not block then
    vim.notify("[codediff] No active conflict at cursor position", vim.log.levels.INFO)
    return false
  end

  local result_bufnr = session.result_bufnr
  local base_lines = session.result_base_lines
  if not result_bufnr or not base_lines then
    vim.notify("[codediff] No result buffer or base lines", vim.log.levels.ERROR)
    return false
  end

  -- Determine first_input based on which side the cursor is on (matches VSCode behavior)
  -- If cursor is on left (incoming), incoming comes first
  -- If cursor is on right (current), current comes first
  local first_input = (side == "left") and 1 or 2

  -- Try smart combination first (like VSCode's "Accept Combination")
  local combined = smart_combine_inputs(session, block, first_input)

  if not combined then
    -- Fallback to dumb combination (concatenate)
    local incoming_lines = tracking.get_lines_for_range(session.original_bufnr, block.output1_range.start_line, block.output1_range.end_line)
    local current_lines = tracking.get_lines_for_range(session.modified_bufnr, block.output2_range.start_line, block.output2_range.end_line)
    combined = dumb_combine_inputs(incoming_lines, current_lines, first_input)
  end

  apply_to_result(result_bufnr, block, combined, base_lines)
  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  return true
end

--- Discard both sides (reset to base) for the conflict under cursor
--- @param tabpage number
--- @return boolean success
function M.discard(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local side = nil

  if current_buf == session.original_bufnr then
    side = "left"
  elseif current_buf == session.modified_bufnr then
    side = "right"
  else
    vim.notify("[codediff] Cursor not in diff buffer", vim.log.levels.WARN)
    return false
  end

  local block = tracking.find_conflict_at_cursor(session, cursor_line, side, true) -- Allow resolved
  if not block then
    vim.notify("[codediff] No conflict at cursor position", vim.log.levels.INFO)
    return false
  end

  -- Get base content for this range. session.merge_base_lines holds the true
  -- merge base (stage :1) so we can index it by base_range coordinates
  -- regardless of what's been auto-merged into the Result seed.
  local base_lines = session.merge_base_lines or session.result_base_lines
  if not base_lines then
    vim.notify("[codediff] No base lines available", vim.log.levels.ERROR)
    return false
  end

  local base_content = {}
  for i = block.base_range.start_line, block.base_range.end_line - 1 do
    table.insert(base_content, base_lines[i] or "")
  end

  local result_bufnr = session.result_bufnr
  if not result_bufnr then
    vim.notify("[codediff] No result buffer", vim.log.levels.ERROR)
    return false
  end

  -- apply_to_result indexes its base_lines parameter by result_range for the
  -- content-search fallback, so pass the Result seed (auto-merged content).
  apply_to_result(result_bufnr, block, base_content, session.result_base_lines or base_lines)
  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  return true
end

--- Accept ALL incoming (left/input1) for all active conflicts
--- @param tabpage number
--- @return boolean success
function M.accept_all_incoming(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  local result_bufnr = session.result_bufnr
  local base_lines = session.result_base_lines
  if not result_bufnr or not base_lines then
    vim.notify("[codediff] No result buffer or base lines", vim.log.levels.ERROR)
    return false
  end

  local count = 0

  -- Process blocks in REVERSE order (bottom-to-top) to avoid line offset issues
  -- Wrap in undojoin for atomic undo
  vim.api.nvim_buf_call(result_bufnr, function()
    for i = #session.conflict_blocks, 1, -1 do
      local block = session.conflict_blocks[i]
      if tracking.is_block_active(session, block) then
        if count > 0 then
          pcall(vim.cmd, "undojoin")
        end
        local incoming_lines = tracking.get_lines_for_range(session.original_bufnr, block.output1_range.start_line, block.output1_range.end_line)
        apply_to_result(result_bufnr, block, incoming_lines, base_lines)
        count = count + 1
      end
    end
  end)

  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  vim.notify(string.format("[codediff] Accepted %d incoming change(s)", count), vim.log.levels.INFO)
  return count > 0
end

--- Accept ALL current (right/input2) for all active conflicts
--- @param tabpage number
--- @return boolean success
function M.accept_all_current(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  local result_bufnr = session.result_bufnr
  local base_lines = session.result_base_lines
  if not result_bufnr or not base_lines then
    vim.notify("[codediff] No result buffer or base lines", vim.log.levels.ERROR)
    return false
  end

  local count = 0

  vim.api.nvim_buf_call(result_bufnr, function()
    for i = #session.conflict_blocks, 1, -1 do
      local block = session.conflict_blocks[i]
      if tracking.is_block_active(session, block) then
        if count > 0 then
          pcall(vim.cmd, "undojoin")
        end
        local current_lines = tracking.get_lines_for_range(session.modified_bufnr, block.output2_range.start_line, block.output2_range.end_line)
        apply_to_result(result_bufnr, block, current_lines, base_lines)
        count = count + 1
      end
    end
  end)

  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  vim.notify(string.format("[codediff] Accepted %d current change(s)", count), vim.log.levels.INFO)
  return count > 0
end

--- Accept ALL both sides for all active conflicts
--- @param tabpage number
--- @param first_input number|nil Which input comes first (1=incoming, 2=current). Default: 1
--- @return boolean success
function M.accept_all_both(tabpage, first_input)
  first_input = first_input or 1

  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  local result_bufnr = session.result_bufnr
  local base_lines = session.result_base_lines
  if not result_bufnr or not base_lines then
    vim.notify("[codediff] No result buffer or base lines", vim.log.levels.ERROR)
    return false
  end

  local count = 0

  vim.api.nvim_buf_call(result_bufnr, function()
    for i = #session.conflict_blocks, 1, -1 do
      local block = session.conflict_blocks[i]
      if tracking.is_block_active(session, block) then
        if count > 0 then
          pcall(vim.cmd, "undojoin")
        end

        local incoming_lines = tracking.get_lines_for_range(session.original_bufnr, block.output1_range.start_line, block.output1_range.end_line)
        local current_lines = tracking.get_lines_for_range(session.modified_bufnr, block.output2_range.start_line, block.output2_range.end_line)

        -- Combine both sides
        local combined
        if first_input == 1 then
          combined = vim.list_extend(vim.list_extend({}, incoming_lines), current_lines)
        else
          combined = vim.list_extend(vim.list_extend({}, current_lines), incoming_lines)
        end

        apply_to_result(result_bufnr, block, combined, base_lines)
        count = count + 1
      end
    end
  end)

  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  vim.notify(string.format("[codediff] Accepted %d combined change(s)", count), vim.log.levels.INFO)
  return count > 0
end

--- Discard ALL changes (reset all conflicts to base)
--- @param tabpage number
--- @return boolean success
function M.discard_all(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    vim.notify("[codediff] No active session", vim.log.levels.WARN)
    return false
  end

  if not session.conflict_blocks or #session.conflict_blocks == 0 then
    vim.notify("[codediff] No conflicts in this session", vim.log.levels.WARN)
    return false
  end

  local result_bufnr = session.result_bufnr
  local seed_lines = session.result_base_lines
  -- Use the true merge base for the slice we write back; the seed only feeds
  -- the content-search fallback in apply_to_result.
  local base_lines = session.merge_base_lines or seed_lines
  if not result_bufnr or not seed_lines or not base_lines then
    vim.notify("[codediff] No result buffer or base lines", vim.log.levels.ERROR)
    return false
  end

  local count = 0

  vim.api.nvim_buf_call(result_bufnr, function()
    for i = #session.conflict_blocks, 1, -1 do
      local block = session.conflict_blocks[i]
      -- For discard, we reset even resolved conflicts back to base
      if count > 0 then
        pcall(vim.cmd, "undojoin")
      end

      local base_content = {}
      for j = block.base_range.start_line, block.base_range.end_line - 1 do
        table.insert(base_content, base_lines[j] or "")
      end

      apply_to_result(result_bufnr, block, base_content, seed_lines)
      count = count + 1
    end
  end)

  signs.refresh_all_conflict_signs(session)
  auto_refresh.refresh_result_now(result_bufnr)
  vim.notify(string.format("[codediff] Reset %d conflict(s) to base", count), vim.log.levels.INFO)
  return count > 0
end

return M
