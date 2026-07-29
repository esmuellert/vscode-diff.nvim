local M = {}

local function prefix(ctx)
  local segments = { { text = ctx.indent, hl = ctx.indent_hl } }
  if ctx.icon ~= "" then
    segments[#segments + 1] = { text = ctx.icon, hl = ctx.icon_hl }
    segments[#segments + 1] = { text = " ", hl = "Normal" }
  end
  return segments
end

local function stat_segments(stats)
  if not stats then
    return {}
  end
  if stats.binary then
    return { { text = "bin", hl = "CodeDiffExplorerStatBinary" } }
  end

  local segments = {}
  if (stats.insertions or 0) > 0 then
    segments[#segments + 1] = { text = "+" .. stats.insertions, hl = "CodeDiffExplorerStatInsertions" }
  end
  if (stats.deletions or 0) > 0 then
    if #segments > 0 then
      segments[#segments + 1] = { text = " ", hl = "Normal" }
    end
    segments[#segments + 1] = { text = "-" .. stats.deletions, hl = "CodeDiffExplorerStatDeletions" }
  end
  return segments
end

local function group_summary(ctx)
  local count_hl = ctx.stats and "CodeDiffExplorerStatFiles" or "CodeDiffExplorerTreeGroup"
  local segments = {
    { text = " (",                     hl = "CodeDiffExplorerTreeGroup" },
    { text = tostring(ctx.file_count), hl = count_hl },
  }
  if ctx.stats and ctx.stats.insertions > 0 then
    segments[#segments + 1] = { text = " · ", hl = "CodeDiffExplorerTreeGroup" }
    segments[#segments + 1] = { text = "+" .. ctx.stats.insertions, hl = "CodeDiffExplorerStatInsertions" }
  end
  if ctx.stats and ctx.stats.deletions > 0 then
    segments[#segments + 1] = { text = ctx.stats.insertions > 0 and " " or " · ", hl = "CodeDiffExplorerTreeGroup" }
    segments[#segments + 1] = { text = "-" .. ctx.stats.deletions, hl = "CodeDiffExplorerStatDeletions" }
  end
  segments[#segments + 1] = { text = ")", hl = "CodeDiffExplorerTreeGroup" }
  return segments
end

function M.file(ctx)
  local left = {
    { segments = prefix(ctx) },
    {
      segments = { { text = ctx.filename, hl = "Normal" } },
      truncate_priority = 2,
    },
  }
  if ctx.directory ~= "" then
    left[#left + 1] = {
      segments = {
        { text = " ",           hl = "Normal" },
        { text = ctx.directory, hl = "ExplorerDirectorySmall" },
      },
      truncate_priority = 1,
    }
  end

  local right = {}
  local stats = stat_segments(ctx.stats)
  if #stats > 0 then
    stats[#stats + 1] = { text = " ", hl = "Normal" }
    right[#right + 1] = { segments = stats, truncate_priority = 3 }
  end
  right[#right + 1] = {
    segments = {
      { text = ctx.status,                               hl = ctx.status_hl },
      { text = string.rep(" ", ctx.status_right_margin), hl = "Normal" },
    },
  }

  return {
    left = left,
    right = right,
    min_gap = 2,
  }
end

function M.folder(ctx)
  return {
    left = {
      { segments = prefix(ctx) },
      {
        segments = { { text = ctx.name, hl = "Directory" } },
        truncate_priority = 1,
      },
    },
    right = {},
    min_gap = 2,
  }
end

function M.group(ctx)
  return {
    left = {
      { segments = { { text = " ", hl = "CodeDiffExplorerTreeGroup" } } },
      {
        segments = { { text = ctx.label, hl = "CodeDiffExplorerTreeGroup" } },
        truncate_priority = 2,
      },
      {
        segments = group_summary(ctx),
        truncate_priority = 1,
      },
    },
    right = {},
    min_gap = 2,
  }
end

return M
