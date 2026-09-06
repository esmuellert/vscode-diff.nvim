local api = vim.api

local M = {}

function M.clamp_line(bufnr, line)
  local line_count = api.nvim_buf_line_count(bufnr)
  return math.max(1, math.min(line, line_count))
end

function M.clamp_window_line(win, line)
  return M.clamp_line(api.nvim_win_get_buf(win), line)
end

function M.clamp_cursor(win, position)
  return {
    M.clamp_window_line(win, position[1]),
    position[2] or 0,
  }
end

return M
