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
  -- Line-level highlights (light background - covers whole line)
  vim.api.nvim_set_hl(0, "VscodeDiffLineInsert", {
    bg = "#1e3a1e",  -- Light green
    default = true,
  })
  
  vim.api.nvim_set_hl(0, "VscodeDiffLineDelete", {
    bg = "#3a1e1e",  -- Light red
    default = true,
  })
  
  -- Character-level highlights (darker background - for specific text)
  vim.api.nvim_set_hl(0, "VscodeDiffCharInsert", {
    bg = "#2d6d2d",  -- Dark green
    default = true,
  })
  
  vim.api.nvim_set_hl(0, "VscodeDiffCharDelete", {
    bg = "#6d2d2d",  -- Dark red
    default = true,
  })
  
  -- Filler lines (gray diagonal pattern)
  vim.api.nvim_set_hl(0, "VscodeDiffFiller", {
    bg = "#2c2c2c",  -- Dark gray
    fg = "#5c5c5c",
    default = true,
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
local function insert_filler_lines(bufnr, after_line_0idx, count)
  if count <= 0 then
    return
  end
  
  -- Clamp to valid range
  if after_line_0idx < 0 then
    after_line_0idx = 0
  end
  
  -- Create virtual lines with filler pattern
  local virt_lines_content = {}
  for i = 1, count do
    table.insert(virt_lines_content, {{"~", "VscodeDiffFiller"}})
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
local function apply_line_highlights(bufnr, line_range, hl_group)
  -- Skip empty ranges
  if line_range.end_line <= line_range.start_line then
    return
  end
  
  -- Apply highlight to entire lines (from column 0 to end of line)
  for line = line_range.start_line, line_range.end_line - 1 do
    local line_idx = line - 1  -- Convert to 0-indexed
    vim.api.nvim_buf_add_highlight(bufnr, ns_highlight, hl_group,
                                   line_idx, 0, -1)  -- 0 to -1 = whole line
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
    -- Single line range
    local line_idx = start_line - 1  -- Convert to 0-indexed
    if line_idx >= 0 then
      vim.api.nvim_buf_add_highlight(bufnr, ns_highlight, hl_group,
                                     line_idx,
                                     start_col - 1,  -- Convert to 0-indexed
                                     end_col - 1)
    end
  else
    -- Multi-line range
    
    -- First line: from start_col to end of line
    local first_line_idx = start_line - 1
    if first_line_idx >= 0 then
      vim.api.nvim_buf_add_highlight(bufnr, ns_highlight, hl_group,
                                     first_line_idx,
                                     start_col - 1,
                                     -1)  -- To end of line
    end
    
    -- Middle lines: entire line
    for line = start_line + 1, end_line - 1 do
      local line_idx = line - 1
      if line_idx >= 0 then
        vim.api.nvim_buf_add_highlight(bufnr, ns_highlight, hl_group,
                                       line_idx, 0, -1)
      end
    end
    
    -- Last line: from start to end_col
    if end_col > 1 then
      local last_line_idx = end_line - 1
      if last_line_idx >= 0 then
        vim.api.nvim_buf_add_highlight(bufnr, ns_highlight, hl_group,
                                       last_line_idx, 0, end_col - 1)
      end
    end
  end
end

-- ============================================================================
-- Step 3: Filler Line Calculation (Simplified for Neovim)
-- ============================================================================

-- Calculate filler lines based on simple empty-range detection
local function calculate_fillers(mapping, original_lines, modified_lines)
  local fillers = {}
  
  -- Skip if no inner changes
  if not mapping.inner_changes or #mapping.inner_changes == 0 then
    return fillers
  end
  
  for idx, inner in ipairs(mapping.inner_changes) do
    local orig_empty = is_empty_range(inner.original)
    local mod_empty = is_empty_range(inner.modified)
    
    -- Debug logging
    print(string.format("[DEBUG] Inner change #%d:", idx))
    print(string.format("  Original: L%d:C%d-L%d:C%d (empty=%s)", 
      inner.original.start_line, inner.original.start_col,
      inner.original.end_line, inner.original.end_col,
      tostring(orig_empty)))
    print(string.format("  Modified: L%d:C%d-L%d:C%d (empty=%s)",
      inner.modified.start_line, inner.modified.start_col,
      inner.modified.end_line, inner.modified.end_col,
      tostring(mod_empty)))
    
    -- Skip if both are empty or both are non-empty
    if orig_empty == mod_empty then
      print("  → Skip: both same state")
      goto continue
    end
    
    -- Check if this is ONLY a line-ending change (no real content)
    -- A line-ending-only change has:
    -- 1. Empty range on one side
    -- 2. Non-empty range on other side that ONLY contains line-ending characters
    local is_line_ending_only = false
    
    if orig_empty and not mod_empty then
      -- Check if modified range is only line endings
      -- If it spans multiple lines or has content beyond line endings, it's real
      if inner.modified.start_line == inner.modified.end_line then
        -- Single line range - check if past content
        is_line_ending_only = is_past_line_content(inner.modified.start_line, inner.modified.start_col, modified_lines)
      end
      -- Multi-line range is always real content
    elseif not orig_empty and mod_empty then
      -- Check if original range is only line endings
      if inner.original.start_line == inner.original.end_line then
        is_line_ending_only = is_past_line_content(inner.original.start_line, inner.original.start_col, original_lines)
      end
    end
    
    print(string.format("  Is line-ending only: %s", tostring(is_line_ending_only)))
    
    -- Skip line-ending-only changes
    if is_line_ending_only then
      print("  → Skip: line-ending change")
      goto continue
    end
    
    if not orig_empty and mod_empty then
      -- Deletion: original has content, modified is empty
      -- Add filler to modified side
      
      -- Calculate actual line count
      local line_count = inner.original.end_line - inner.original.start_line
      -- If end_col > 1, we touched the end line, so include it
      if inner.original.end_col > 1 then
        line_count = line_count + 1
      end
      
      print(string.format("  → DELETION: orig lines %d-%d, end_col=%d, count=%d",
        inner.original.start_line, inner.original.end_line, inner.original.end_col, line_count))
      print(string.format("  → Add %d filler(s) to MODIFIED after line %d",
        line_count, inner.modified.start_line - 1))
      
      if line_count > 0 then
        table.insert(fillers, {
          buffer = 'modified',
          after_line = inner.modified.start_line - 1,  -- BEFORE the range
          count = line_count
        })
      end
      
    elseif orig_empty and not mod_empty then
      -- Insertion: original is empty, modified has content
      -- Add filler to original side
      
      -- Calculate actual line count
      -- For multi-line ranges, this is the number of full lines affected
      local line_count
      if inner.modified.start_line == inner.modified.end_line then
        -- Single line change
        line_count = 1
      else
        -- Multi-line change: count the lines spanned
        -- If start_col == 1, we're changing from beginning of start line
        -- If end_col == 1, we end BEFORE end line (don't include it)
        line_count = inner.modified.end_line - inner.modified.start_line
        if inner.modified.end_col > 1 then
          line_count = line_count + 1
        end
      end
      
      print(string.format("  → INSERTION: mod lines %d-%d, start_col=%d, end_col=%d, count=%d",
        inner.modified.start_line, inner.modified.end_line, 
        inner.modified.start_col, inner.modified.end_col, line_count))
      print(string.format("  → Add %d filler(s) to ORIGINAL after line %d",
        line_count, inner.original.start_line - 1))
      
      if line_count > 0 then
        table.insert(fillers, {
          buffer = 'original',
          after_line = inner.original.start_line - 1,  -- BEFORE the range
          count = line_count
        })
      end
    end
    
    ::continue::
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
  for mapping_idx, mapping in ipairs(lines_diff.changes) do
    print(string.format("\n[DEBUG] Processing mapping #%d", mapping_idx))
    print(string.format("  Original range: L%d-%d", mapping.original.start_line, mapping.original.end_line))
    print(string.format("  Modified range: L%d-%d", mapping.modified.start_line, mapping.modified.end_line))
    
    -- Check if ranges are empty
    local orig_is_empty = (mapping.original.end_line <= mapping.original.start_line)
    local mod_is_empty = (mapping.modified.end_line <= mapping.modified.start_line)
    
    print(string.format("  Original empty: %s, Modified empty: %s", tostring(orig_is_empty), tostring(mod_is_empty)))
    
    -- STEP 1: Apply line-level highlights (light colors, whole lines)
    if not orig_is_empty then
      apply_line_highlights(left_bufnr, mapping.original, "VscodeDiffLineDelete")
      print("  → Applied line highlight to ORIGINAL")
    end
    
    if not mod_is_empty then
      apply_line_highlights(right_bufnr, mapping.modified, "VscodeDiffLineInsert")
      print("  → Applied line highlight to MODIFIED")
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
    
    print(string.format("  Calculated %d filler(s)", #fillers))
    
    for _, filler in ipairs(fillers) do
      print(string.format("  → Inserting %d filler(s) to %s after line %d (0-indexed: %d)",
        filler.count, filler.buffer, filler.after_line, filler.after_line - 1))
      
      if filler.buffer == 'original' then
        insert_filler_lines(left_bufnr, filler.after_line - 1, filler.count)
        total_left_fillers = total_left_fillers + filler.count
      else
        insert_filler_lines(right_bufnr, filler.after_line - 1, filler.count)
        total_right_fillers = total_right_fillers + filler.count
      end
    end
  end
  
  print(string.format("\n[DEBUG] Total fillers: left=%d, right=%d", total_left_fillers, total_right_fillers))
  
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
