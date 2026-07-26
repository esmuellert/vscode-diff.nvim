local M = {}

local function region(segments, options)
  return vim.tbl_extend("force", { segments = segments }, options or {})
end

local function file_prefix(ctx)
  local segments = { { text = ctx.indent, hl = ctx.indent_hl } }
  if ctx.icon ~= "" then
    segments[#segments + 1] = { text = ctx.icon, hl = ctx.icon_hl }
    segments[#segments + 1] = { text = " ", hl = "Normal" }
  end
  return segments
end

function M.file(ctx)
  local left = {
    region(file_prefix(ctx)),
    region({ { text = ctx.filename, hl = "Normal" } }, { truncate_priority = 2 }),
  }
  if ctx.directory ~= "" then
    left[#left + 1] = region({
      { text = " ", hl = "Normal" },
      { text = ctx.directory, hl = "ExplorerDirectorySmall" },
    }, { truncate_priority = 1 })
  end

  return {
    left = left,
    right = {
      region({
        { text = ctx.status, hl = ctx.status_hl },
        { text = string.rep(" ", ctx.status_right_margin), hl = "Normal" },
      }),
    },
    min_gap = 2,
  }
end

function M.folder(ctx)
  local prefix = { { text = ctx.indent, hl = ctx.indent_hl } }
  if ctx.icon ~= "" then
    prefix[#prefix + 1] = { text = ctx.icon, hl = ctx.icon_hl }
    prefix[#prefix + 1] = { text = " ", hl = "Normal" }
  end
  return {
    left = {
      region(prefix),
      region({ { text = ctx.name, hl = "Directory" } }, { truncate_priority = 1 }),
    },
    right = {},
    min_gap = 2,
  }
end

function M.group(ctx)
  return {
    left = {
      region({ { text = " ", hl = "CodeDiffExplorerTreeGroup" } }),
      region({ { text = ctx.label, hl = "CodeDiffExplorerTreeGroup" } }, { truncate_priority = 2 }),
      region({ { text = string.format(" (%d)", ctx.file_count), hl = "CodeDiffExplorerTreeGroup" } }, { truncate_priority = 1 }),
    },
    right = {},
    min_gap = 2,
  }
end

return M
