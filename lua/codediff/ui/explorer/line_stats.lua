local M = {}

function M.sum(files)
  local total = {
    files_changed = #files,
    insertions = 0,
    deletions = 0,
    binary_files = 0,
    unavailable_files = 0,
  }
  for _, file in ipairs(files) do
    local stats = file.line_stats
    if not stats then
      total.unavailable_files = total.unavailable_files + 1
    elseif stats.binary then
      total.binary_files = total.binary_files + 1
    else
      total.insertions = total.insertions + (stats.insertions or 0)
      total.deletions = total.deletions + (stats.deletions or 0)
    end
  end
  return total
end

return M
