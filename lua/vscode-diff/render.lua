-- Simplified Rendering Module for Neovim Grid-Based Diff
-- This uses a simplified approach optimized for Neovim's fixed-height grid:
-- 1. Line-level highlights (light colors) for entire changed line ranges
-- 2. Character-level highlights (dark colors) for specific changed text
-- 3. Filler lines based on simple empty-range detection

local M = {}

-- Namespaces
local ns_highlight = vim.api.nvim_create_namespace("vscode-diff-highlight")
local ns_filler = vim.api.nvim_create_namespace("vscode-diff-filler")

-- Setup VSCode-style highlight groups
function M.setup_highlights()
  -- Get native diff colors to use as base
  local diff_add = vim.api.nvim_get_hl(0, {name = "DiffAdd"})
  local diff_delete = vim.api.nvim_get_hl(0, {name = "DiffDelete"})

  -- Helper function to adjust color brightness
  local function adjust_brightness(color, factor)
    if not color then return nil end
    local r = math.floor(color / 65536) % 256
    local g = math.floor(color / 256) % 256
    local b = color % 256

    -- Apply factor and clamp to 0-255
    r = math.min(255, math.floor(r * factor))
    g = math.min(255, math.floor(g * factor))
    b = math.min(255, math.floor(b * factor))

    return r * 65536 + g * 256 + b
  end

  -- REVERSED STRATEGY:
  -- Line-level (whole line background): DARKER, subtle
  -- Char-level (specific text): BRIGHTER, stands out

  -- Line-level highlights: DARKER versions (70% of native)
  vim.api.nvim_set_hl(0, "VscodeDiffLineInsert", {
    bg = adjust_brightness(diff_add.bg, 0.7) or 0x1d3042,  -- Darker green
    default = true,
  })

  vim.api.nvim_set_hl(0, "VscodeDiffLineDelete", {
    bg = adjust_brightness(diff_delete.bg, 0.7) or 0x351d2b,  -- Darker red
    default = true,
  })

  -- Character-level highlights: BRIGHTER versions (use native or 1.2x)
  -- These should stand out ON TOP of the darker line background
  vim.api.nvim_set_hl(0, "VscodeDiffCharInsert", {
    bg = diff_add.bg or 0x2a4556,  -- Full brightness green (native DiffAdd)
    default = true,
  })

  vim.api.nvim_set_hl(0, "VscodeDiffCharDelete", {
    bg = diff_delete.bg or 0x4b2a3d,  -- Full brightness red (native DiffDelete)
    default = true,
  })

  -- Filler lines (no highlight, inherits editor default background)
  vim.api.nvim_set_hl(0, "VscodeDiffFiller", {
    fg = "#444444",  -- Subtle gray for the slash character
    default = true,
    -- No bg set - uses editor's default background
  })
end

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Check if a range is empty (start and end are the same position)
local function is_empty_range(range)
  return range.start_line == range.end_line and
         range.start_col == range.end_col
end

-- Check if a column position is past the visible line content
-- This detects line-ending-only changes (\r\n handling)
local function is_past_line_content(line_number, column, lines)
  if line_number < 1 or line_number > #lines then
    return true
  end
  local line_content = lines[line_number]
  return column > #line_content
end

-- Insert virtual filler lines using extmarks
-- Style matching diffview.nvim - uses diagonal slash pattern filling the whole line
local function insert_filler_lines(bufnr, after_line_0idx, count)
  if count <= 0 then
    return
  end

  -- Clamp to valid range
  if after_line_0idx < 0 then
    after_line_0idx = 0
  end

  -- Create virtual lines with diagonal slash pattern (diffview.nvim style)
  -- Uses "╱" (U+2571 BOX DRAWINGS LIGHT DIAGONAL UPPER RIGHT TO LOWER LEFT)
  local virt_lines_content = {}
  
  -- Use a large number of characters to ensure it fills any reasonable window width
  -- The rendering will clip it to the actual window width automatically
  local filler_text = string.rep("╱", 500)
  
  for i = 1, count do
    table.insert(virt_lines_content, {{filler_text, "VscodeDiffFiller"}})
  end

  vim.api.nvim_buf_set_extmark(bufnr, ns_filler, after_line_0idx, 0, {
    virt_lines = virt_lines_content,
    virt_lines_above = false,
  })
end

-- ============================================================================
-- Step 1: Line-Level Highlights (Light Colors)
-- ============================================================================

-- Apply light background color to entire line ranges in the mapping
-- Uses hl_eol to extend highlight to cover the whole screen line
local function apply_line_highlights(bufnr, line_range, hl_group)
  -- Skip empty ranges
  if line_range.end_line <= line_range.start_line then
    return
  end

  -- Get buffer line count to avoid going out of bounds
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  -- Apply highlight to entire lines using hl_eol
  -- This highlights the entire screen line including the area beyond EOL
  for line = line_range.start_line, line_range.end_line - 1 do
    if line > line_count then
      break
    end

    local line_idx = line - 1  -- Convert to 0-indexed

    -- Use hl_eol to extend highlight to the whole screen line
    -- Priority 100 = lower than char highlights (200) so char highlights remain visible
    vim.api.nvim_buf_set_extmark(bufnr, ns_highlight, line_idx, 0, {
      end_line = line_idx + 1,
      end_col = 0,
      hl_group = hl_group,
      hl_eol = true,  -- KEY: Extend highlight to cover the whole screen line
      priority = 100,
    })
  end
end

-- ============================================================================
-- Step 2: Character-Level Highlights (Dark Colors)
-- ============================================================================

-- Apply character-level highlight for specific changed text
local function apply_char_highlight(bufnr, char_range, hl_group, lines)
  local start_line = char_range.start_line
  local start_col = char_range.start_col
  local end_line = char_range.end_line
  local end_col = char_range.end_col

  -- Skip empty ranges
  if is_empty_range(char_range) then
    return
  end

  -- Skip line-ending-only changes (column past visible content)
  if is_past_line_content(start_line, start_col, lines) then
    return
  end

  -- Clamp end column to line content length
  if end_line >= 1 and end_line <= #lines then
    local line_content = lines[end_line]
    end_col = math.min(end_col, #line_content + 1)
  end

  if start_line == end_line then
    -- Single line range - use extmark with HIGH priority to override line highlight
    local line_idx = start_line - 1  -- Convert to 0-indexed
    if line_idx >= 0 then
      vim.api.nvim_buf_set_extmark(bufnr, ns_highlight, line_idx, start_col - 1, {
        end_col = end_col - 1,
        hl_group = hl_group,
        priority = 200,  -- Higher than line highlight (100)
      })
    end
  else
    -- Multi-line range

    -- First line: from start_col to end of line
    local first_line_idx = start_line - 1
    if first_line_idx >= 0 then
      vim.api.nvim_buf_set_extmark(bufnr, ns_highlight, first_line_idx, start_col - 1, {
        end_line = first_line_idx + 1,
        end_col = 0,  -- To start of next line (= end of this line)
        hl_group = hl_group,
        priority = 200,
      })
    end

    -- Middle lines: entire line
    for line = start_line + 1, end_line - 1 do
      local line_idx = line - 1
      if line_idx >= 0 then
        vim.api.nvim_buf_set_extmark(bufnr, ns_highlight, line_idx, 0, {
          end_line = line_idx + 1,
          end_col = 0,  -- Entire line
          hl_group = hl_group,
          priority = 200,
        })
      end
    end

    -- Last line: from start to end_col
    -- Only process if end_col > 1 OR if end_line is different from first_line
    if end_col > 1 or end_line ~= start_line then
      local last_line_idx = end_line - 1
      if last_line_idx >= 0 and last_line_idx ~= first_line_idx then
        vim.api.nvim_buf_set_extmark(bufnr, ns_highlight, last_line_idx, 0, {
          end_col = end_col - 1,
          hl_group = hl_group,
          priority = 200,
        })
      end
    end
  end
end

-- ============================================================================
-- Step 3: Filler Line Calculation (Simplified for Neovim)
-- ============================================================================

-- Calculate filler lines based on inner changes
-- Simple rule: For each inner change, if one side is single-line but the other is multi-line,
-- add filler lines to align them.
-- Positioning:
--   - Leading insertions/deletions (first inner change at column 1): BEFORE the line
--   - All other insertions/expansions: AFTER the line  
--   - All other deletions/collapses: BEFORE the line (because content was removed)
local function calculate_fillers(mapping, original_lines, modified_lines)
  local fillers = {}

  -- Process each inner change
  if mapping.inner_changes and #mapping.inner_changes > 0 then
    for idx, inner in ipairs(mapping.inner_changes) do
      local orig_line_count = inner.original.end_line - inner.original.start_line
      local mod_line_count = inner.modified.end_line - inner.modified.start_line
      
      -- Calculate the difference in line counts
      local line_diff = mod_line_count - orig_line_count
      
      -- Skip if both sides are single-line (no multi-line expansion/collapse)
      if orig_line_count == 0 and mod_line_count == 0 then
        goto continue
      end
      
      -- Determine if this is a LEADING change (first inner change starting at column 1)
      local is_first_change = (idx == 1)
      local starts_at_col_1 = (inner.original.start_col == 1 and inner.modified.start_col == 1)
      local is_leading_change = is_first_change and starts_at_col_1
      
      -- If there's a difference, one side needs fillers
      if line_diff > 0 then
        -- Modified has more lines: add fillers to original
        local after_line
        if is_leading_change then
          -- Leading insertion: BEFORE the line
          after_line = inner.original.start_line - 1
        else
          -- Inline expansion: AFTER the line
          after_line = inner.original.start_line
        end
        
        table.insert(fillers, {
          buffer = 'original',
          after_line = after_line,
          count = line_diff
        })
      elseif line_diff < 0 then
        -- Original has more lines: add fillers to modified
        local after_line
        if is_leading_change then
          -- Leading deletion: BEFORE the line
          after_line = inner.modified.start_line - 1
        else
          -- Trailing/inline deletion: BEFORE the line (content was removed)
          after_line = inner.modified.start_line - 1
        end
        
        table.insert(fillers, {
          buffer = 'modified',
          after_line = after_line,
          count = -line_diff
        })
      end
      
      ::continue::
    end
    
    return fillers
  end
  
  -- Fallback: Use simple line count difference for mappings without inner changes
  -- This handles cases where entire blocks are added/removed
  local mapping_orig_lines = mapping.original.end_line - mapping.original.start_line
  local mapping_mod_lines = mapping.modified.end_line - mapping.modified.start_line
  
  if mapping_orig_lines > mapping_mod_lines then
    local diff = mapping_orig_lines - mapping_mod_lines
    table.insert(fillers, {
      buffer = 'modified',
      after_line = mapping.modified.start_line - 1,
      count = diff
    })
  elseif mapping_mod_lines > mapping_orig_lines then
    local diff = mapping_mod_lines - mapping_orig_lines
    table.insert(fillers, {
      buffer = 'original',
      after_line = mapping.original.start_line - 1,
      count = diff
    })
  end

  return fillers
end

-- ============================================================================
-- Main Rendering Function
-- ============================================================================

-- Render diff with simplified 3-step algorithm
function M.render_diff(left_bufnr, right_bufnr, original_lines, modified_lines, lines_diff)
  -- Clear existing highlights and fillers
  vim.api.nvim_buf_clear_namespace(left_bufnr, ns_highlight, 0, -1)
  vim.api.nvim_buf_clear_namespace(right_bufnr, ns_highlight, 0, -1)
  vim.api.nvim_buf_clear_namespace(left_bufnr, ns_filler, 0, -1)
  vim.api.nvim_buf_clear_namespace(right_bufnr, ns_filler, 0, -1)

  -- Set buffer content
  vim.api.nvim_buf_set_lines(left_bufnr, 0, -1, false, original_lines)
  vim.api.nvim_buf_set_lines(right_bufnr, 0, -1, false, modified_lines)

  local total_left_fillers = 0
  local total_right_fillers = 0

  -- Process each change mapping
  for _, mapping in ipairs(lines_diff.changes) do
    -- Check if ranges are empty
    local orig_is_empty = (mapping.original.end_line <= mapping.original.start_line)
    local mod_is_empty = (mapping.modified.end_line <= mapping.modified.start_line)

    -- STEP 1: Apply line-level highlights (light colors, whole lines)
    if not orig_is_empty then
      apply_line_highlights(left_bufnr, mapping.original, "VscodeDiffLineDelete")
    end

    if not mod_is_empty then
      apply_line_highlights(right_bufnr, mapping.modified, "VscodeDiffLineInsert")
    end

    -- STEP 2: Apply character-level highlights (dark colors, specific text)
    if mapping.inner_changes then
      for _, inner in ipairs(mapping.inner_changes) do
        -- Apply to original side
        if not is_empty_range(inner.original) then
          apply_char_highlight(left_bufnr, inner.original,
                             "VscodeDiffCharDelete", original_lines)
        end

        -- Apply to modified side
        if not is_empty_range(inner.modified) then
          apply_char_highlight(right_bufnr, inner.modified,
                             "VscodeDiffCharInsert", modified_lines)
        end
      end
    end

    -- STEP 3: Calculate and insert filler lines
    local fillers = calculate_fillers(mapping, original_lines, modified_lines)

    for _, filler in ipairs(fillers) do
      if filler.buffer == 'original' then
        insert_filler_lines(left_bufnr, filler.after_line - 1, filler.count)
        total_left_fillers = total_left_fillers + filler.count
      else
        insert_filler_lines(right_bufnr, filler.after_line - 1, filler.count)
        total_right_fillers = total_right_fillers + filler.count
      end
    end
  end

  return {
    left_fillers = total_left_fillers,
    right_fillers = total_right_fillers,
  }
end

-- Create side-by-side diff view
function M.create_diff_view(original_lines, modified_lines, lines_diff)
  -- Create buffers
  local left_buf = vim.api.nvim_create_buf(false, true)
  local right_buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  local buf_opts = {
    modifiable = false,
    buftype = "nofile",
    bufhidden = "wipe",
  }

  for opt, val in pairs(buf_opts) do
    vim.api.nvim_buf_set_option(left_buf, opt, val)
    vim.api.nvim_buf_set_option(right_buf, opt, val)
  end

  -- Temporarily make buffers modifiable for content and filler insertion
  vim.api.nvim_buf_set_option(left_buf, "modifiable", true)
  vim.api.nvim_buf_set_option(right_buf, "modifiable", true)

  -- Render diff (this inserts fillers and applies highlights)
  local result = M.render_diff(left_buf, right_buf, original_lines, modified_lines, lines_diff)

  -- Make buffers read-only again
  vim.api.nvim_buf_set_option(left_buf, "modifiable", false)
  vim.api.nvim_buf_set_option(right_buf, "modifiable", false)

  -- Create side-by-side windows
  vim.cmd("tabnew")
  local left_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left_win, left_buf)

  vim.cmd("vsplit")
  local right_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right_win, right_buf)

  -- Window options
  local win_opts = {
    number = true,
    relativenumber = false,
    cursorline = true,
    scrollbind = true,  -- Synchronized scrolling
  }

  for opt, val in pairs(win_opts) do
    vim.api.nvim_win_set_option(left_win, opt, val)
    vim.api.nvim_win_set_option(right_win, opt, val)
  end

  -- Set buffer names (make unique)
  local unique_id = math.random(1000000, 9999999)
  pcall(vim.api.nvim_buf_set_name, left_buf, string.format("Original_%d", unique_id))
  pcall(vim.api.nvim_buf_set_name, right_buf, string.format("Modified_%d", unique_id))

  vim.notify(string.format("Diff view created: %d changes, %d left fillers, %d right fillers",
    #lines_diff.changes, result.left_fillers, result.right_fillers), vim.log.levels.INFO)

  return {
    left_buf = left_buf,
    right_buf = right_buf,
    left_win = left_win,
    right_win = right_win,
    result = result,
  }
end

return M
