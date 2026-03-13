-- Shared floating window helpers for CodeDiff UI modules.
local M = {}

---@param border any
---@return boolean
function M.border_is_none(border)
  if border == nil then
    return false
  end

  if type(border) == "string" then
    return border == "" or border:lower() == "none"
  end

  if type(border) == "table" and type(border.style) == "string" then
    return border.style:lower() == "none"
  end

  return false
end

---@param opts? { filetype?: string }
---@return integer bufnr
function M.create_scratch_buf(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  if opts.filetype then
    vim.bo[bufnr].filetype = opts.filetype
  end
  return bufnr
end

---@param winid integer
---@param winhighlight string
function M.set_float_win_options(winid, winhighlight)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = false
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].winhighlight = winhighlight
end

---@param win_config table
---@param border any
---@param title string?
---@param title_pos string?
---@param footer string?
---@param footer_pos string?
function M.apply_title_footer(win_config, border, title, title_pos, footer, footer_pos)
  if M.border_is_none(border) then
    return
  end
  if vim.fn.has("nvim-0.9") ~= 1 then
    return
  end
  if title then
    win_config.title = title
    win_config.title_pos = title_pos or "left"
  end
  if footer and vim.fn.has("nvim-0.10") == 1 then
    win_config.footer = footer
    win_config.footer_pos = footer_pos or "left"
  end
end

---@param existing_winid integer?
---@param bufnr integer
---@param enter boolean
---@param win_config table
---@return integer winid
function M.open_or_reconfigure(existing_winid, bufnr, enter, win_config)
  if existing_winid and vim.api.nvim_win_is_valid(existing_winid) then
    pcall(vim.api.nvim_win_set_config, existing_winid, win_config)
    return existing_winid
  end
  return vim.api.nvim_open_win(bufnr, enter, win_config)
end

return M
