-- Rendering module for applying diff highlights
local M = {}
local config = require("vscode-diff.config")

-- Define VSCode-style highlight groups
-- Based on VSCode's style.css and registrations.contribution.ts
function M.setup_highlights()
  -- Line-level highlights (light backgrounds)
  -- Using RGB colors that approximate VSCode's appearance
  vim.api.nvim_set_hl(0, "VscodeDiffLineInsert", {
    bg = "#1e3a1e",  -- Dark green background (approximation for dark theme)
    default = true,
  })
  
  vim.api.nvim_set_hl(0, "VscodeDiffLineDelete", {
    bg = "#3a1e1e",  -- Dark red background (approximation for dark theme)
    default = true,
  })
  
  -- Character-level highlights (deep/dark colors - THE "DEEPER COLOR" EFFECT)
  vim.api.nvim_set_hl(0, "VscodeDiffCharInsert", {
    bg = "#2d6d2d",  -- Deeper/darker green for inserted characters
    default = true,
  })
  
  vim.api.nvim_set_hl(0, "VscodeDiffCharDelete", {
    bg = "#6d2d2d",  -- Deeper/darker red for deleted characters
    default = true,
  })
end

-- Get namespace for highlights
local ns_id = vim.api.nvim_create_namespace("vscode-diff")

-- Apply highlights to a buffer based on render plan
function M.apply_highlights(bufnr, side_plan)
  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  
  for _, meta in ipairs(side_plan.line_metadata) do
    if not meta.is_filler and meta.line_num > 0 then
      local line_idx = meta.line_num - 1  -- Convert to 0-indexed
      
      -- Apply line-level highlight for changed lines
      -- HL_NONE is -1, which appears as 4294967295 in Lua FFI (unsigned)
      -- So we check for the specific valid types instead
      local is_changed_line = (meta.type == 0 or meta.type == 1)  -- INSERT or DELETE
      
      if is_changed_line then
        local line_hl_group
        if meta.type == 0 then  -- HL_LINE_INSERT
          line_hl_group = "VscodeDiffLineInsert"
        elseif meta.type == 1 then  -- HL_LINE_DELETE
          line_hl_group = "VscodeDiffLineDelete"
        end
        
        if line_hl_group then
          vim.api.nvim_buf_add_highlight(bufnr, ns_id, line_hl_group, line_idx, 0, -1)
        end
      end
      
      -- Apply character-level highlights (the "deeper color" effect)
      for _, char_hl in ipairs(meta.char_highlights) do
        local char_hl_group
        if char_hl.type == 2 then  -- HL_CHAR_INSERT
          char_hl_group = "VscodeDiffCharInsert"
        elseif char_hl.type == 3 then  -- HL_CHAR_DELETE
          char_hl_group = "VscodeDiffCharDelete"
        end
        
        if char_hl_group then
          -- Convert to 0-indexed columns
          local start_col = char_hl.start_col - 1
          local end_col = char_hl.end_col - 1
          vim.api.nvim_buf_add_highlight(bufnr, ns_id, char_hl_group, line_idx, start_col, end_col)
        end
      end
    end
  end
end

-- Add filler lines using virtual text
function M.add_filler_lines(bufnr, side_plan)
  local extmark_ns = vim.api.nvim_create_namespace("vscode-diff-filler")
  
  for i, meta in ipairs(side_plan.line_metadata) do
    if meta.is_filler then
      -- Add virtual line at the appropriate position
      -- Find the previous real line
      local prev_line = 0
      for j = i - 1, 1, -1 do
        if not side_plan.line_metadata[j].is_filler then
          prev_line = side_plan.line_metadata[j].line_num
          break
        end
      end
      
      -- Add extmark with virtual line
      if prev_line > 0 then
        vim.api.nvim_buf_set_extmark(bufnr, extmark_ns, prev_line - 1, 0, {
          virt_lines = {{{"~", "NonText"}}},  -- Array of line chunks
          virt_lines_above = false,
        })
      end
    end
  end
end

-- Render diff in two side-by-side buffers
function M.render_diff(lines_a, lines_b, render_plan)
  -- Create two new buffers
  local buf_left = vim.api.nvim_create_buf(false, true)
  local buf_right = vim.api.nvim_create_buf(false, true)
  
  -- Set buffer content
  vim.api.nvim_buf_set_lines(buf_left, 0, -1, false, lines_a)
  vim.api.nvim_buf_set_lines(buf_right, 0, -1, false, lines_b)
  
  -- Apply buffer options
  for opt, val in pairs(config.options.buffer_options) do
    vim.api.nvim_buf_set_option(buf_left, opt, val)
    vim.api.nvim_buf_set_option(buf_right, opt, val)
  end
  
  -- Apply highlights
  M.apply_highlights(buf_left, render_plan.left)
  M.apply_highlights(buf_right, render_plan.right)
  
  -- Add filler lines
  M.add_filler_lines(buf_left, render_plan.left)
  M.add_filler_lines(buf_right, render_plan.right)
  
  -- Create side-by-side windows in a new tab
  vim.cmd("tabnew")
  local win_left = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win_left, buf_left)
  
  vim.cmd("vsplit")
  local win_right = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win_right, buf_right)
  
  -- Apply window options
  for opt, val in pairs(config.options.window_options) do
    vim.api.nvim_win_set_option(win_left, opt, val)
    vim.api.nvim_win_set_option(win_right, opt, val)
  end
  
  -- Count highlights applied for user feedback
  local left_count = 0
  local right_count = 0
  for _, meta in ipairs(render_plan.left.line_metadata) do
    if not meta.is_filler then
      -- Count line-level highlights (type 0 or 1 = INSERT or DELETE)
      if meta.type == 0 or meta.type == 1 then
        left_count = left_count + 1
      end
      left_count = left_count + #meta.char_highlights  -- Char hls
    end
  end
  for _, meta in ipairs(render_plan.right.line_metadata) do
    if not meta.is_filler then
      -- Count line-level highlights (type 0 or 1 = INSERT or DELETE)
      if meta.type == 0 or meta.type == 1 then
        right_count = right_count + 1
      end
      right_count = right_count + #meta.char_highlights  -- Char hls
    end
  end
  
  vim.notify(string.format("Diff rendered: %d highlights (left: %d, right: %d). Note: Enable 'termguicolors' if colors don't show.",
    left_count + right_count, left_count, right_count), vim.log.levels.INFO)
  
  return {
    buf_left = buf_left,
    buf_right = buf_right,
    win_left = win_left,
    win_right = win_right,
  }
end

return M
