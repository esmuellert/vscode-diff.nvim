-- Computes the initial auto-merged Result content.
local M = {}

local compute_mapping_alignments = require("codediff.ui.conflict.merge.alignment").compute_mapping_alignments

--- Compute the auto-merged Result buffer content.
--- Ports VSCode's MergeEditorModel.computeAutoMergedResult().
--- For each base-range group:
---   * only input1 changed -> take input1 lines
---   * only input2 changed -> take input2 lines
---   * both changed identically -> take input1 lines
---   * both changed differently (conflict) -> keep base lines (user resolves)
--- Lines outside any group are copied straight from base.
---
--- Also returns conflict_blocks with `result_range` (1-based, inclusive start /
--- exclusive end) marking where each unresolved conflict lives in the merged
--- buffer, so extmark tracking can anchor to merged-content line numbers
--- instead of pure-base line numbers.
---
--- @param base_to_input1_diff table { changes = {...} }
--- @param base_to_input2_diff table { changes = {...} }
--- @param base_lines string[]
--- @param input1_lines string[]
--- @param input2_lines string[]
--- @return string[] merged_lines, table[] conflict_blocks
function M.compute_auto_merged_result(base_to_input1_diff, base_to_input2_diff, base_lines, input1_lines, input2_lines)
  local mapping_alignments = compute_mapping_alignments(base_to_input1_diff.changes, base_to_input2_diff.changes)

  local result_lines = {}
  local conflict_blocks = {}

  local function append_range(source, start_line, end_line_exclusive)
    for i = start_line, end_line_exclusive - 1 do
      table.insert(result_lines, source[i] or "")
    end
  end

  local function ranges_equal_content(s1, r1, s2, r2)
    local len1 = r1.end_line - r1.start_line
    local len2 = r2.end_line - r2.start_line
    if len1 ~= len2 then
      return false
    end
    for i = 0, len1 - 1 do
      if (s1[r1.start_line + i] or "") ~= (s2[r2.start_line + i] or "") then
        return false
      end
    end
    return true
  end

  local base_cursor = 1 -- 1-based line index into base_lines, inclusive

  for _, ma in ipairs(mapping_alignments) do
    -- Copy unchanged base lines preceding this group.
    append_range(base_lines, base_cursor, ma.base_range.start_line)
    base_cursor = ma.base_range.end_line

    local has1 = ma.has_input1
    local has2 = ma.has_input2

    if has1 and not has2 then
      append_range(input1_lines, ma.output1_range.start_line, ma.output1_range.end_line)
    elseif has2 and not has1 then
      append_range(input2_lines, ma.output2_range.start_line, ma.output2_range.end_line)
    elseif has1 and has2 and ranges_equal_content(input1_lines, ma.output1_range, input2_lines, ma.output2_range) then
      -- Both sides made the identical change -> not a conflict, apply once.
      append_range(input1_lines, ma.output1_range.start_line, ma.output1_range.end_line)
    else
      -- True conflict: keep base, leave for the user to resolve.
      local conflict_start = #result_lines + 1
      append_range(base_lines, ma.base_range.start_line, ma.base_range.end_line)
      local conflict_end_exclusive = #result_lines + 1
      table.insert(conflict_blocks, {
        base_range = ma.base_range,
        output1_range = ma.output1_range,
        output2_range = ma.output2_range,
        inner1 = ma.inner1,
        inner2 = ma.inner2,
        result_range = { start_line = conflict_start, end_line = conflict_end_exclusive },
      })
    end
  end

  -- Copy any remaining base lines after the last group.
  append_range(base_lines, base_cursor, #base_lines + 1)

  return result_lines, conflict_blocks
end

return M
