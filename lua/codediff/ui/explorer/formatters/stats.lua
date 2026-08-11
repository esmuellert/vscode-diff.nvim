-- Line-stats rendering helpers.
--
-- Active only when `explorer.line_stats.enabled = true` — that config path is
-- what populates `ctx.stats` on file, folder, and group contexts. When the
-- feature is disabled, `ctx.stats` is nil and each helper returns a shape that
-- makes the default rows collapse back to their pre-line-stats output.

local M = {}

-- File row: right-hand `+N -N` segments (or `bin` for binary files, or an
-- empty list when no stats are attached).
function M.file_segments(stats)
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

-- Group row: headline `(N)` (feature disabled) or `(N · +42 -8)` (enabled).
function M.group_summary(ctx)
  local count_hl = ctx.stats and "CodeDiffExplorerStatFiles" or "CodeDiffExplorerTreeGroup"
  local segments = {
    { text = " (", hl = "CodeDiffExplorerTreeGroup" },
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

return M
