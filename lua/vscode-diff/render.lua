-- Rendering module using VSCode's computeRangeAlignment algorithm
-- Takes LinesDiff from diff.lua and renders side-by-side with proper alignment

local M = {}

-- Namespaces
local ns_highlight = vim.api.nvim_create_namespace("vscode-diff-highlight")
local ns_filler = vim.api.nvim_create_namespace("vscode-diff-filler")

-- Line height simulation (in conceptual units)
-- Neovim doesn't have pixel-based heights, so we work with line counts
local LINE_HEIGHT = 1

-- Setup VSCode-style highlight groups
function M.setup_highlights()
  -- Line-level highlights (light background)
  vim.api.nvim_set_hl(0, "VscodeDiffLineInsert", {
    bg = "#1e3a1e",  -- Light green
    default = true,
  })
  
  vim.api.nvim_set_hl(0, "VscodeDiffLineDelete", {
    bg = "#3a1e1e",  -- Light red
    default = true,
  })
  
  -- Character-level highlights (dark background - "deeper color")
  vim.api.nvim_set_hl(0, "VscodeDiffCharInsert", {
    bg = "#2d6d2d",  -- Dark green
    default = true,
  })
  
  vim.api.nvim_set_hl(0, "VscodeDiffCharDelete", {
    bg = "#6d2d2d",  -- Dark red
    default = true,
  })
  
  -- Filler lines (gray)
  vim.api.nvim_set_hl(0, "VscodeDiffFiller", {
    bg = "#2c2c2c",  -- Dark gray
    fg = "#5c5c5c",
    default = true,
  })
end

-- ============================================================================
-- Simple Line-Count Based Alignment (for side-by-side mode)
-- ============================================================================
-- Note: The complex VSCode alignment algorithm with sub-line segments is not
-- needed for Neovim side-by-side mode because:
-- 1. Neovim uses line-based heights (not pixel-based)
-- 2. Virtual lines don't wrap
-- 3. Unchanged regions naturally align with scrollbind
-- 4. We only need fillers where total line counts differ in changed regions

-- ============================================================================
-- Filler Line Insertion
-- ============================================================================

-- Insert virtual filler lines using extmarks
-- These are visual-only lines that don't modify the actual buffer content
local function insert_filler_lines(bufnr, after_line_0idx, count)
  if count <= 0 then
    return 0
  end
  
  -- Create ONE extmark with the specified number of virtual lines
  local virt_lines_content = {}
  for i = 1, count do
    table.insert(virt_lines_content, {{"~", "VscodeDiffFiller"}})
  end
  
  vim.api.nvim_buf_set_extmark(bufnr, ns_filler, after_line_0idx, 0, {
    virt_lines = virt_lines_content,
    virt_lines_above = false,
  })
  
  return 0  -- Virtual lines don't change line count
end

-- ============================================================================
-- Character Highlight Application
-- ============================================================================

-- Apply character-level highlight (handles multi-line ranges)
local function apply_char_highlight(bufnr, char_range, offset, hl_group, lines)
  local start_line = char_range.start_line
  local start_col = char_range.start_col
  local end_line = char_range.end_line
  local end_col = char_range.end_col
  
  -- Skip empty ranges
  if start_line == end_line and start_col >= end_col then
    return
  end
  
  if start_line == end_line then
    -- Single line range
    local line_idx = start_line - 1 + offset
    vim.api.nvim_buf_add_highlight(bufnr, ns_highlight, hl_group,
                                   line_idx,
                                   start_col - 1,  -- Convert to 0-indexed
                                   end_col - 1)
  else
    -- Multi-line range: split into first/middle/last
    
    -- First line: from start_col to end of line
    local first_line_idx = start_line - 1 + offset
    vim.api.nvim_buf_add_highlight(bufnr, ns_highlight, hl_group,
                                   first_line_idx,
                                   start_col - 1,
                                   -1)  -- To end of line
    
    -- Middle lines: entire line
    for line = start_line + 1, end_line - 1 do
      local line_idx = line - 1 + offset
      vim.api.nvim_buf_add_highlight(bufnr, ns_highlight, hl_group,
                                     line_idx, 0, -1)
    end
    
    -- Last line: from start to end_col
    if end_col > 1 then
      local last_line_idx = end_line - 1 + offset
      vim.api.nvim_buf_add_highlight(bufnr, ns_highlight, hl_group,
                                     last_line_idx, 0, end_col - 1)
    end
  end
end

-- ============================================================================
-- Main Rendering Function
-- ============================================================================

-- Render diff with alignment following VSCode's algorithm
function M.render_diff(left_bufnr, right_bufnr, original_lines, modified_lines, lines_diff)
  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(left_bufnr, ns_highlight, 0, -1)
  vim.api.nvim_buf_clear_namespace(right_bufnr, ns_highlight, 0, -1)
  vim.api.nvim_buf_clear_namespace(left_bufnr, ns_filler, 0, -1)
  vim.api.nvim_buf_clear_namespace(right_bufnr, ns_filler, 0, -1)
  
  -- Set buffer content first
  vim.api.nvim_buf_set_lines(left_bufnr, 0, -1, false, original_lines)
  vim.api.nvim_buf_set_lines(right_bufnr, 0, -1, false, modified_lines)
  
  -- Track last processed line numbers (like VSCode's computeRangeAlignment)
  local last_orig_line = 1
  local last_mod_line = 1
  
  -- Process each change mapping
  for _, mapping in ipairs(lines_diff.changes) do
    -- Handle gap BEFORE this diff (unchanged region between diffs)
    -- This is the critical part missing from the simple approach!
    local gap_orig = mapping.original.start_line - last_orig_line
    local gap_mod = mapping.modified.start_line - last_mod_line
    
    if gap_mod > gap_orig then
      -- More unchanged lines on modified side before this diff
      -- Add fillers to original side BEFORE the diff starts
      local filler_count = gap_mod - gap_orig
      -- Place fillers at the END of the unchanged region on original side
      -- That's at line (last_orig_line + gap_orig - 1), converted to 0-indexed
      local filler_line_0idx = last_orig_line + gap_orig - 1
      if filler_line_0idx >= 0 then
        insert_filler_lines(left_bufnr, filler_line_0idx, filler_count)
      end
    elseif gap_orig > gap_mod then
      -- More unchanged lines on original side before this diff
      -- Add fillers to modified side BEFORE the diff starts  
      local filler_count = gap_orig - gap_mod
      local filler_line_0idx = last_mod_line + gap_mod - 1
      if filler_line_0idx >= 0 then
        insert_filler_lines(right_bufnr, filler_line_0idx, filler_count)
      end
    end
    -- Clamp mapping ranges to actual file sizes (C code sometimes returns beyond bounds)
    local clamped_mapping = {
      original = {
        start_line = mapping.original.start_line,
        end_line = math.min(mapping.original.end_line, #original_lines + 1)
      },
      modified = {
        start_line = mapping.modified.start_line,
        end_line = math.min(mapping.modified.end_line, #modified_lines + 1)
      },
      inner_changes = mapping.inner_changes
    }
    
    -- Determine which lines to highlight
    -- Highlight lines that have actual content changes
    local left_lines_to_highlight = {}
    local right_lines_to_highlight = {}
    
    for _, inner in ipairs(mapping.inner_changes) do
      -- Left side: highlight if it has actual content (not just an insertion point)
      if inner.original.start_col < inner.original.end_col then
        for line = inner.original.start_line, inner.original.end_line do
          if line <= #original_lines then
            left_lines_to_highlight[line] = true
          end
        end
      else
        -- Empty on original (insertion point) but has content on modified
        -- Highlight the original line too (visual indicator of the diff)
        -- But only if the insertion point is not at the very start (C1-C1 is before the line)
        if inner.modified.start_col < inner.modified.end_col and 
           not (inner.original.start_col == 1 and inner.original.end_col == 1) then
          for line = inner.original.start_line, inner.original.end_line do
            if line <= #original_lines and line < mapping.original.end_line then
              left_lines_to_highlight[line] = true
            end
          end
        end
      end
      
      -- Right side: highlight if it has actual content (not just an insertion point)
      if inner.modified.start_col < inner.modified.end_col then
        for line = inner.modified.start_line, inner.modified.end_line do
          if line <= #modified_lines then
            right_lines_to_highlight[line] = true
          end
        end
      else
        -- Empty on modified (insertion point) but has content on original
        -- Highlight the modified line too (visual indicator of the diff)
        -- But only if the insertion point is not at the very start (C1-C1 is before the line)
        if inner.original.start_col < inner.original.end_col and
           not (inner.modified.start_col == 1 and inner.modified.end_col == 1) then
          for line = inner.modified.start_line, inner.modified.end_line do
            if line <= #modified_lines and line < mapping.modified.end_line then
              right_lines_to_highlight[line] = true
            end
          end
        end
      end
    end
    
    -- Apply line-level highlights to lines with actual changes
    for line, _ in pairs(left_lines_to_highlight) do
      local line_idx = line - 1  -- Convert to 0-indexed
      vim.api.nvim_buf_add_highlight(left_bufnr, ns_highlight, "VscodeDiffLineDelete",
                                     line_idx, 0, -1)
    end
    
    for line, _ in pairs(right_lines_to_highlight) do
      local line_idx = line - 1  -- Convert to 0-indexed
      vim.api.nvim_buf_add_highlight(right_bufnr, ns_highlight, "VscodeDiffLineInsert",
                                     line_idx, 0, -1)
    end
    
    -- Apply character-level highlights
    for _, inner in ipairs(mapping.inner_changes) do
      apply_char_highlight(left_bufnr, inner.original, 0,
                          "VscodeDiffCharDelete", original_lines)
      apply_char_highlight(right_bufnr, inner.modified, 0,
                          "VscodeDiffCharInsert", modified_lines)
    end
    
    -- Inner-hunk alignment (like VSCode's innerHunkAlignment)
    -- Process innerChanges to create sub-alignments within the diff
    
    -- Special case: If the mapping has empty original range but innerChanges reference lines,
    -- those lines should be treated as part of the mapping
    local actual_orig_start = mapping.original.start_line
    local actual_orig_end = mapping.original.end_line
    
    -- Find the actual line range covered by innerChanges
    for _, inner in ipairs(mapping.inner_changes) do
      if inner.original.start_col < inner.original.end_col then
        -- Original side has content
        actual_orig_end = math.max(actual_orig_end, inner.original.end_line + 1)
      end
    end
    
    local last_inner_orig = actual_orig_start
    local last_inner_mod = mapping.modified.start_line
    
    for idx, inner in ipairs(mapping.inner_changes) do
      -- VSCode creates alignments at innerChange boundaries:
      -- 1. If there's unmodified text BEFORE the change (both start_col > 1)
      -- 2. If there's unmodified text AFTER the change (end_col < max_col)
      
      local orig_line = original_lines[inner.original.end_line]
      local mod_line = modified_lines[inner.modified.end_line]
      local orig_max_col = orig_line and (#orig_line + 1) or 1
      local mod_max_col = mod_line and (#mod_line + 1) or 1
      
      -- Check for unmodified text BEFORE the innerChange
      -- Only create alignment if BOTH sides start on the SAME line
      if inner.original.start_line == inner.modified.start_line and
         inner.original.start_col > 1 and inner.modified.start_col > 1 then
        -- There's unmodified text before this change on both sides
        -- Create alignment at the START of the innerChange
        local inner_orig_delta = inner.original.start_line - last_inner_orig
        local inner_mod_delta = inner.modified.start_line - last_inner_mod
        
        if inner_mod_delta > inner_orig_delta then
          local filler_count = inner_mod_delta - inner_orig_delta
          local filler_line_0idx = last_inner_orig - 1
          if filler_line_0idx >= 0 and filler_count > 0 then
            insert_filler_lines(left_bufnr, filler_line_0idx, filler_count)
          end
        elseif inner_orig_delta > inner_mod_delta then
          local filler_count = inner_orig_delta - inner_mod_delta
          local filler_line_0idx = last_inner_mod - 1
          if filler_line_0idx >= 0 and filler_count > 0 then
            insert_filler_lines(right_bufnr, filler_line_0idx, filler_count)
          end
        end
        
        last_inner_orig = inner.original.start_line
        last_inner_mod = inner.modified.start_line
      end
      
      -- Check for unmodified text AFTER the innerChange
      if inner.original.end_col < orig_max_col or inner.modified.end_col < mod_max_col then
        -- VSCode uses exclusive end line numbers
        -- When end_col < max_col, the line is partial, so end_line is already the last line touched
        -- Special case: end_col == 1 means we end at the START of that line (not touching it)
        -- Only add +1 if we consumed the entire line (end_col == max_col)
        local inner_orig_end_exclusive
        if inner.original.end_col == 1 then
          -- Ends at column 1 = ends BEFORE this line
          inner_orig_end_exclusive = inner.original.end_line
        elseif inner.original.end_col >= orig_max_col then
          -- Consumed entire line
          inner_orig_end_exclusive = inner.original.end_line + 1
        else
          -- Partial line
          inner_orig_end_exclusive = inner.original.end_line
        end
        
        local inner_mod_end_exclusive
        if inner.modified.end_col == 1 then
          inner_mod_end_exclusive = inner.modified.end_line
        elseif inner.modified.end_col >= mod_max_col then
          inner_mod_end_exclusive = inner.modified.end_line + 1
        else
          inner_mod_end_exclusive = inner.modified.end_line
        end
        
        local inner_orig_delta = inner_orig_end_exclusive - last_inner_orig
        local inner_mod_delta = inner_mod_end_exclusive - last_inner_mod
        
        if inner_mod_delta > inner_orig_delta then
          local filler_count = inner_mod_delta - inner_orig_delta
          -- Place fillers AFTER the segment end
          -- Special case: if original is empty (start_col == end_col), place before the line
          local filler_line_0idx
          if inner.original.start_col == inner.original.end_col then
            -- Empty range (insertion point) - place fillers BEFORE this line
            filler_line_0idx = inner.original.start_line - 2
          elseif inner.original.end_col == 1 then
            -- Ends at column 1 = ends at START of line = didn't touch this line
            -- Place after the PREVIOUS line
            filler_line_0idx = inner.original.end_line - 2
          elseif inner.original.end_col >= orig_max_col then
            -- Full line consumed - use exclusive end
            filler_line_0idx = inner_orig_end_exclusive - 2
          else
            -- Partial line - use inclusive end
            filler_line_0idx = inner_orig_end_exclusive - 1
          end
          if filler_line_0idx >= 0 and filler_count > 0 then
            insert_filler_lines(left_bufnr, filler_line_0idx, filler_count)
          end
        elseif inner_orig_delta > inner_mod_delta then
          local filler_count = inner_orig_delta - inner_mod_delta
          local filler_line_0idx
          if inner.modified.start_col == inner.modified.end_col then
            filler_line_0idx = inner.modified.start_line - 2
          elseif inner.modified.end_col == 1 then
            filler_line_0idx = inner.modified.end_line - 2
          elseif inner.modified.end_col >= mod_max_col then
            filler_line_0idx = inner_mod_end_exclusive - 2
          else
            filler_line_0idx = inner_mod_end_exclusive - 1
          end
          if filler_line_0idx >= 0 and filler_count > 0 then
            insert_filler_lines(right_bufnr, filler_line_0idx, filler_count)
          end
        end
        
        last_inner_orig = inner_orig_end_exclusive
        last_inner_mod = inner_mod_end_exclusive
      end
    end
    
    -- Final alignment at the end of the mapping (for any remaining lines)
    local final_orig_delta = mapping.original.end_line - last_inner_orig
    local final_mod_delta = mapping.modified.end_line - last_inner_mod
    
    if final_mod_delta > final_orig_delta then
      local filler_count = final_mod_delta - final_orig_delta
      local filler_line_0idx = last_inner_orig - 1
      if filler_line_0idx >= 0 and filler_count > 0 then
        insert_filler_lines(left_bufnr, filler_line_0idx, filler_count)
      end
    elseif final_orig_delta > final_mod_delta then
      local filler_count = final_orig_delta - final_mod_delta
      local filler_line_0idx = last_inner_mod - 1
      if filler_line_0idx >= 0 and filler_count > 0 then
        insert_filler_lines(right_bufnr, filler_line_0idx, filler_count)
      end
    end
    
    -- Update tracking for next iteration
    last_orig_line = mapping.original.end_line
    last_mod_line = mapping.modified.end_line
  end
  
  return {
    left_offset = 0,
    right_offset = 0,
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
    #lines_diff.changes, result.left_offset, result.right_offset), vim.log.levels.INFO)
  
  return {
    left_buf = left_buf,
    right_buf = right_buf,
    left_win = left_win,
    right_win = right_win,
    result = result,
  }
end

return M
