-- Replaces a tracked conflict range in the Result buffer.
local M = {}

local tracking = require("codediff.ui.conflict.tracking")

--- Apply text to result buffer at the conflict's range
--- @param result_bufnr number Result buffer
--- @param block table Conflict block with base_range and optional extmark_id
--- @param lines table Lines to insert
--- @param base_lines table Result-buffer seed content (auto-merged result),
---                       used only for the content-search fallback when the
---                       extmark is invalid. Indexed by result_range, falling
---                       back to base_range for legacy paths.
function M.apply_to_result(result_bufnr, block, lines, base_lines)
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

return M
