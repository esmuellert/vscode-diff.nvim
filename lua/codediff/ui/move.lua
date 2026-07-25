-- Moved code rendering: highlights, signs, annotation virt_lines, and filler alignment
local M = {}

local highlights = require("codediff.ui.highlights")
local filler_renderer = require("codediff.ui.filler")
local ns_highlight = highlights.ns_highlight

-- ============================================================================
-- Change Lookup Helpers
-- ============================================================================

-- Find which change (if any) contains a given original-side line
local function find_change_for_orig(line, changes)
  for _, c in ipairs(changes) do
    if line >= c.original.start_line and line < c.original.end_line then
      return c
    end
  end
end

-- Find which change (if any) contains a given modified-side line
local function find_change_for_mod(line, changes)
  for _, c in ipairs(changes) do
    if line >= c.modified.start_line and line < c.modified.end_line then
      return c
    end
  end
end

-- ============================================================================
-- Cross-Side Alignment Helpers
-- ============================================================================

-- Walk through changes to find which mod line aligns with an orig line
local function find_aligned_mod_line(orig_line, changes)
  local offset = 0
  for _, c in ipairs(changes) do
    if orig_line < c.original.start_line then
      return orig_line + offset
    end
    if orig_line >= c.original.start_line and orig_line < c.original.end_line then
      return c.modified.start_line
    end
    local orig_consumed = c.original.end_line - c.original.start_line
    local mod_consumed = c.modified.end_line - c.modified.start_line
    offset = offset + (mod_consumed - orig_consumed)
  end
  return orig_line + offset
end

-- Walk through changes to find which orig line aligns with a mod line
local function find_aligned_orig_line(mod_line, changes)
  local offset = 0
  for _, c in ipairs(changes) do
    if mod_line < c.modified.start_line then
      return mod_line + offset
    end
    if mod_line >= c.modified.start_line and mod_line < c.modified.end_line then
      return c.original.start_line
    end
    local orig_consumed = c.original.end_line - c.original.start_line
    local mod_consumed = c.modified.end_line - c.modified.start_line
    offset = offset + (orig_consumed - mod_consumed)
  end
  return mod_line + offset
end

-- ============================================================================
-- Per-Line Highlights and Signs
-- ============================================================================

local function get_sign(line, first, last)
  if first == last then
    return "─"
  end
  if line == first then
    return "┌"
  end
  if line == last then
    return "└"
  end
  return "│"
end

local function highlight_moved_lines(bufnr, first, last, line_count)
  for line = first, last do
    if line > line_count then
      break
    end
    local line_idx = line - 1
    local sign = get_sign(line, first, last)
    -- Range extmark for highlight (overrides diff highlight at priority 250)
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_highlight, line_idx, 0, {
      end_line = line_idx + 1,
      end_col = 0,
      hl_group = "CodeDiffLineMove",
      hl_eol = true,
      priority = 250,
    })
    -- Separate point extmark for sign + number highlight (no end_line — won't bleed)
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_highlight, line_idx, 0, {
      number_hl_group = "CodeDiffMoveTo",
      sign_text = sign,
      sign_hl_group = "CodeDiffMoveTo",
      priority = 250,
    })
  end
end

-- ============================================================================
-- Annotation Filler Position
-- ============================================================================

-- Compute the filler anchor and above flag for a compensating filler on the
-- opposite side of an annotation virt_line.
local function compute_filler_position(annotation_line, change, is_orig_side, changes, other_line_count)
  local filler_anchor
  local filler_above = true

  if change then
    local same_start, other_start, same_lines, other_lines, other_end
    if is_orig_side then
      same_start = change.original.start_line
      other_start = change.modified.start_line
      other_lines = change.modified.end_line - change.modified.start_line
      other_end = change.modified.end_line
    else
      same_start = change.modified.start_line
      other_start = change.original.start_line
      other_lines = change.original.end_line - change.original.start_line
      other_end = change.original.end_line
    end
    local offset_in_change = annotation_line - same_start

    if offset_in_change < other_lines then
      filler_anchor = other_start + offset_in_change - 1
    elseif other_lines > 0 then
      filler_anchor = other_end - 2
      filler_above = false
    else
      filler_anchor = math.max(other_start - 2, 0)
      filler_above = (filler_anchor == 0)
    end
  else
    local aligned
    if is_orig_side then
      aligned = find_aligned_mod_line(annotation_line, changes)
    else
      aligned = find_aligned_orig_line(annotation_line, changes)
    end
    filler_anchor = math.max(aligned - 1, 0)
  end

  filler_anchor = math.min(filler_anchor, other_line_count - 1)
  return filler_anchor, filler_above
end

-- ============================================================================
-- Annotation Placement
-- ============================================================================

local function place_annotation(ann_bufnr, filler_bufnr, ann_line, label, change, is_orig_side, changes, filler_line_count)
  local anchor = math.max(ann_line - 1, 0)
  pcall(vim.api.nvim_buf_set_extmark, ann_bufnr, ns_highlight, anchor, 0, {
    virt_lines = { { { label, "CodeDiffMoveTo" } } },
    virt_lines_above = true,
    priority = 250,
  })

  local filler_anchor, filler_above = compute_filler_position(ann_line, change, is_orig_side, changes, filler_line_count)
  pcall(filler_renderer.place, filler_bufnr, filler_anchor, 1, {
    above = filler_above,
    priority = 250,
  })
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Render all moved code indicators on both buffers.
--- @param left_bufnr number original buffer
--- @param right_bufnr number modified buffer
--- @param lines_diff table diff result with .moves and .changes
function M.render_moves(left_bufnr, right_bufnr, lines_diff)
  if not lines_diff.moves or #lines_diff.moves == 0 then
    return
  end

  local orig_line_count = vim.api.nvim_buf_line_count(left_bufnr)
  local mod_line_count = vim.api.nvim_buf_line_count(right_bufnr)

  for _, move in ipairs(lines_diff.moves) do
    local orig_first = move.original.start_line
    local orig_last = move.original.end_line - 1
    local mod_first = move.modified.start_line
    local mod_last = move.modified.end_line - 1

    -- Line highlights and signs on both sides
    highlight_moved_lines(left_bufnr, orig_first, orig_last, orig_line_count)
    highlight_moved_lines(right_bufnr, mod_first, mod_last, mod_line_count)

    -- Annotation + filler on both sides
    local label = "⇄ moved: L" .. orig_first .. "-" .. orig_last .. " → L" .. mod_first .. "-" .. mod_last

    if orig_first <= orig_line_count then
      local change = find_change_for_orig(orig_first, lines_diff.changes)
      place_annotation(left_bufnr, right_bufnr, orig_first, label, change, true, lines_diff.changes, mod_line_count)
    end

    if mod_first <= mod_line_count then
      local change = find_change_for_mod(mod_first, lines_diff.changes)
      place_annotation(right_bufnr, left_bufnr, mod_first, label, change, false, lines_diff.changes, orig_line_count)
    end
  end
end

return M
