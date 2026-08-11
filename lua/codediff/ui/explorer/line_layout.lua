local Line = require("codediff.ui.lib.line")
local line_highlights = require("codediff.ui.explorer.line_highlights")

local M = {}

local function display_width(text)
  return vim.fn.strdisplaywidth(text or "")
end

local function segments_width(segments)
  local width = 0
  for _, segment in ipairs(segments or {}) do
    width = width + display_width(segment.text)
  end
  return width
end

local function regions_width(regions)
  local width = 0
  for _, region in ipairs(regions) do
    width = width + segments_width(region.segments)
  end
  return width
end

local function copy_regions(regions)
  local copied = {}
  for _, region in ipairs(regions or {}) do
    if region.truncate_priority ~= nil and type(region.truncate_priority) ~= "number" then
      error("Explorer formatter region truncate_priority must be numeric")
    end

    local segments = {}
    for _, segment in ipairs(region.segments or {}) do
      if segment.text and segment.text ~= "" then
        segments[#segments + 1] = { text = tostring(segment.text), hl = segment.hl }
      end
    end
    if #segments > 0 then
      copied[#copied + 1] = {
        segments = segments,
        truncate_priority = region.truncate_priority,
      }
    end
  end
  return copied
end

local function append_text(segments, text, hl)
  if text == "" then
    return
  end
  local previous = segments[#segments]
  if previous and previous.hl == hl then
    previous.text = previous.text .. text
  else
    segments[#segments + 1] = { text = text, hl = hl }
  end
end

local function fit_text(text, max_width)
  local fitted = ""
  local width = 0
  for index = 0, vim.fn.strchars(text) - 1 do
    local char = vim.fn.strcharpart(text, index, 1)
    local char_width = display_width(char)
    if width + char_width > max_width then
      return fitted
    end
    fitted = fitted .. char
    width = width + char_width
  end
  return fitted
end

local function truncate_segments(segments, max_width, ellipsis)
  if max_width <= 0 then
    return {}
  end
  if segments_width(segments) <= max_width then
    return segments
  end

  ellipsis = fit_text(ellipsis, max_width)
  local prefix_width = max_width - display_width(ellipsis)
  local truncated = {}
  local width = 0
  local ellipsis_hl = segments[1] and segments[1].hl or "Normal"

  for _, segment in ipairs(segments) do
    for index = 0, vim.fn.strchars(segment.text) - 1 do
      local char = vim.fn.strcharpart(segment.text, index, 1)
      local char_width = display_width(char)
      if width + char_width > prefix_width then
        append_text(truncated, ellipsis, ellipsis_hl)
        return truncated
      end
      append_text(truncated, char, segment.hl)
      ellipsis_hl = segment.hl
      width = width + char_width
    end
  end

  append_text(truncated, ellipsis, ellipsis_hl)
  return truncated
end

local function layout_width(left, right, min_gap)
  local left_width = regions_width(left)
  local right_width = regions_width(right)
  local gap = left_width > 0 and right_width > 0 and min_gap or 0
  return left_width + gap + right_width
end

local function shrink_region(region, overflow, ellipsis)
  local width = segments_width(region.segments)
  region.segments = truncate_segments(region.segments, math.max(0, width - overflow), ellipsis)
end

local function shrink_priorities(left, right, max_width, min_gap, ellipsis)
  local candidates = {}
  for _, regions in ipairs({ left, right }) do
    for _, region in ipairs(regions) do
      if region.truncate_priority then
        candidates[#candidates + 1] = region
      end
    end
  end
  table.sort(candidates, function(a, b)
    return a.truncate_priority < b.truncate_priority
  end)

  for _, region in ipairs(candidates) do
    local overflow = layout_width(left, right, min_gap) - max_width
    if overflow <= 0 then
      return
    end
    shrink_region(region, overflow, ellipsis)
  end
end

local function shrink_fixed_left(left, right, max_width, min_gap, ellipsis)
  for index = #left, 1, -1 do
    local overflow = layout_width(left, right, min_gap) - max_width
    if overflow <= 0 then
      return
    end
    shrink_region(left[index], overflow, ellipsis)
  end
end

local function shrink_fixed_right(left, right, max_width, min_gap, ellipsis)
  for index = 1, #right do
    local overflow = layout_width(left, right, min_gap) - max_width
    if overflow <= 0 then
      return
    end
    shrink_region(right[index], overflow, ellipsis)
  end
end

local function append_regions(line, regions, selected_bg)
  for _, region in ipairs(regions) do
    for _, segment in ipairs(region.segments) do
      line:append(segment.text, line_highlights.resolve(segment.hl, selected_bg))
    end
  end
end

function M.render(layout, max_width, selected_bg, ellipsis)
  if type(layout) ~= "table" then
    error("Explorer formatters must return a line layout")
  end
  ellipsis = ellipsis == nil and "…" or ellipsis
  if type(ellipsis) ~= "string" then
    error("Explorer ellipsis must be a string")
  end
  local left = copy_regions(layout.left)
  local right = copy_regions(layout.right)
  local min_gap = math.max(0, layout.min_gap or 2)
  max_width = math.max(0, max_width)

  shrink_priorities(left, right, max_width, min_gap, ellipsis)
  if layout_width(left, right, min_gap) > max_width then
    min_gap = math.max(0, min_gap - (layout_width(left, right, min_gap) - max_width))
  end
  shrink_fixed_left(left, right, max_width, min_gap, ellipsis)
  shrink_fixed_right(left, right, max_width, min_gap, ellipsis)

  local line = Line()
  local left_width = regions_width(left)
  local right_width = regions_width(right)
  append_regions(line, left, selected_bg)
  if right_width > 0 then
    local gap = left_width > 0 and min_gap or 0
    local padding = math.max(gap, max_width - left_width - right_width)
    line:append(string.rep(" ", padding), line_highlights.resolve("Normal", selected_bg))
    append_regions(line, right, selected_bg)
  end
  return line
end

return M
