-- Simplified Rendering Module for Neovim Grid-Based Diff
-- This uses a simplified approach optimized for Neovim's fixed-height grid:
-- 1. Line-level highlights (dimmed colors) for entire changed line ranges
-- 2. Character-level highlights (full brightness) for specific changed text
-- 3. Filler lines based on simple empty-range detection

local M = {}
local config = require('vscode-diff.config')

-- Namespaces
local ns_highlight = vim.api.nvim_create_namespace("vscode-diff-highlight")
local ns_filler = vim.api.nvim_create_namespace("vscode-diff-filler")

-- Setup VSCode-style highlight groups
function M.setup_highlights()
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

  -- Get base highlight colors from config
  local line_insert_hl = vim.api.nvim_get_hl(0, { name = config.options.highlights.line_insert })
  local line_delete_hl = vim.api.nvim_get_hl(0, { name = config.options.highlights.line_delete })
  local char_brightness = config.options.highlights.char_brightness

  -- Line-level highlights: Use base colors directly (DiffAdd, DiffDelete)
  vim.api.nvim_set_hl(0, "VscodeDiffLineInsert", {
    bg = line_insert_hl.bg or 0x1d3042,  -- Fallback to default green
    default = true,
  })

  vim.api.nvim_set_hl(0, "VscodeDiffLineDelete", {
    bg = line_delete_hl.bg or 0x351d2b,  -- Fallback to default red
    default = true,
  })

  -- Character-level highlights: Brighter versions of line highlights
  vim.api.nvim_set_hl(0, "VscodeDiffCharInsert", {
    bg = adjust_brightness(line_insert_hl.bg, char_brightness) or 0x2a4556,  -- Brighter green
    default = true,
  })

  vim.api.nvim_set_hl(0, "VscodeDiffCharDelete", {
    bg = adjust_brightness(line_delete_hl.bg, char_brightness) or 0x4b2a3d,  -- Brighter red
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

  for _ = 1, count do
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
-- VSCode rule (from diffEditorViewZones.ts): 
--   Fillers are placed after `range.endLineNumberExclusive - 1`
-- 
-- Important: VSCode uses EXCLUSIVE end ranges [start, end), we use INCLUSIVE [start, end]
-- Conversion: VSCode's `endLineExclusive - 1` equals our `end_line`
--   Example for single line 35:
--     VSCode: startLine=35, endLineExclusive=36 → afterLineNumber = 36-1 = 35
--     Us:     start_line=35, end_line=35       → after_line = 35
-- Calculate filler lines based on inner changes
-- Based on VSCode's computeRangeAlignment in diffEditorViewZones.ts
--
-- VSCode's approach: Create alignments at the START and END lines of inner changes
-- - If inner change starts mid-line (col > 1): create alignment at START line
-- - If inner change ends before EOL: create alignment at END line
-- - Then view zones (fillers) are placed at alignment.endLineNumberExclusive - 1
--
-- For leading insertions (like line 1216), no alignment is created at the start
-- (since col=1), so the alignment from the previous region ends BEFORE the insertion,
-- placing fillers above the inserted content.
local function calculate_fillers(mapping, original_lines, _modified_lines, last_orig_line, last_mod_line)
  local fillers = {}

  -- Initialize tracking from parameters (for global gap handling)
  -- If not provided, default to mapping start (backward compatibility)
  last_orig_line = last_orig_line or mapping.original.start_line
  last_mod_line = last_mod_line or mapping.modified.start_line

  if not mapping.inner_changes or #mapping.inner_changes == 0 then
    -- Fallback: no inner changes, use simple line count difference
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
    return fillers, mapping.original.end_line, mapping.modified.end_line
  end

  -- Track alignments (where original and modified lines should align)
  local alignments = {}
  local first = true  -- VSCode's 'first' flag to allow initial alignment

  -- Handle gap alignment before processing inner changes (VSCode's handleAlignmentsOutsideOfDiffs)
  -- This creates alignment for any gap between the last processed line and this mapping's start
  local function handle_gap_alignment(orig_line_exclusive, mod_line_exclusive)
    local orig_gap = orig_line_exclusive - last_orig_line
    local mod_gap = mod_line_exclusive - last_mod_line

    if orig_gap > 0 or mod_gap > 0 then
      table.insert(alignments, {
        orig_start = last_orig_line,
        orig_end = orig_line_exclusive,
        mod_start = last_mod_line,
        mod_end = mod_line_exclusive,
        orig_len = orig_gap,
        mod_len = mod_gap
      })
      last_orig_line = orig_line_exclusive
      last_mod_line = mod_line_exclusive
    end
  end

  -- Emit gap alignment before processing this mapping's inner changes
  handle_gap_alignment(mapping.original.start_line, mapping.modified.start_line)

  local function emit_alignment(orig_line_exclusive, mod_line_exclusive)
    -- Skip if going backwards
    if orig_line_exclusive < last_orig_line or mod_line_exclusive < last_mod_line then
      return
    end

    -- VSCode's logic: skip redundant alignments, but allow the first one
    if first then
      first = false
    elseif orig_line_exclusive == last_orig_line or mod_line_exclusive == last_mod_line then
      return
    end

    local orig_range_len = orig_line_exclusive - last_orig_line
    local mod_range_len = mod_line_exclusive - last_mod_line

    if orig_range_len > 0 or mod_range_len > 0 then
      table.insert(alignments, {
        orig_start = last_orig_line,
        orig_end = orig_line_exclusive,
        mod_start = last_mod_line,
        mod_end = mod_line_exclusive,
        orig_len = orig_range_len,
        mod_len = mod_range_len
      })
    end

    last_orig_line = orig_line_exclusive
    last_mod_line = mod_line_exclusive
  end

  -- Process inner changes to create alignments (VSCode's innerHunkAlignment logic)
  for _, inner in ipairs(mapping.inner_changes) do
    -- If there's unmodified text BEFORE the diff on this line (column > 1)
    if inner.original.start_col > 1 and inner.modified.start_col > 1 then
      emit_alignment(inner.original.start_line, inner.modified.start_line)
    end

    -- If there's unmodified text AFTER the diff on this line
    -- Check if the change ends before the end of the line
    local orig_line_len = original_lines[inner.original.end_line] and #original_lines[inner.original.end_line] or 0
    if inner.original.end_col <= orig_line_len then
      -- CharRange.end_line is inclusive; emit_alignment uses this directly
      -- for AFTER alignments (aligning the unchanged suffix on the same line)
      emit_alignment(inner.original.end_line, inner.modified.end_line)
    end
  end

  -- Final alignment at the end of the mapping (mapping ranges use EXCLUSIVE end)
  emit_alignment(mapping.original.end_line, mapping.modified.end_line)

  -- Convert alignments to fillers
  -- VSCode: afterLineNumber = range.endLineNumberExclusive - 1
  -- Our ranges are inclusive, so: after_line = end_line - 1
  for _, align in ipairs(alignments) do
    local line_diff = align.mod_len - align.orig_len

    if line_diff > 0 then
      -- Modified has more lines
      table.insert(fillers, {
        buffer = 'original',
        after_line = align.orig_end - 1,
        count = line_diff
      })
    elseif line_diff < 0 then
      -- Original has more lines
      table.insert(fillers, {
        buffer = 'modified',
        after_line = align.mod_end - 1,
        count = -line_diff
      })
    end
  end

  -- Return fillers and updated tracking state for next mapping
  return fillers, last_orig_line, last_mod_line
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

  -- Track last processed line across all mappings for gap alignment (VSCode behavior)
  local last_orig_line = 1  -- Start from line 1
  local last_mod_line = 1

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
    local fillers, new_last_orig, new_last_mod = calculate_fillers(
      mapping, original_lines, modified_lines, last_orig_line, last_mod_line
    )

    -- Update global tracking state
    last_orig_line = new_last_orig
    last_mod_line = new_last_mod

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
    vim.bo[left_buf][opt] = val
    vim.bo[right_buf][opt] = val
  end

  -- Temporarily make buffers modifiable for content and filler insertion
  vim.bo[left_buf].modifiable = true
  vim.bo[right_buf].modifiable = true

  -- Render diff (this inserts fillers and applies highlights)
  local result = M.render_diff(left_buf, right_buf, original_lines, modified_lines, lines_diff)

  -- Make buffers read-only again
  vim.bo[left_buf].modifiable = false
  vim.bo[right_buf].modifiable = false

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
    vim.wo[left_win][opt] = val
    vim.wo[right_win][opt] = val
  end

  -- Set buffer names (make unique)
  local unique_id = math.random(1000000, 9999999)
  pcall(vim.api.nvim_buf_set_name, left_buf, string.format("Original_%d", unique_id))
  pcall(vim.api.nvim_buf_set_name, right_buf, string.format("Modified_%d", unique_id))

  return {
    left_buf = left_buf,
    right_buf = right_buf,
    left_win = left_win,
    right_win = right_win,
    result = result,
  }
end

return M
