-- Configuration module
local M = {}

M.defaults = {
  -- Highlight groups (will be defined in render.lua)
  highlights = {
    line_insert = "DiffAdd",
    line_delete = "DiffDelete",
    char_insert = "DiffText",
    char_delete = "DiffText",
  },
  
  -- Buffer options
  buffer_options = {
    modifiable = false,
    readonly = true,
    buftype = "nofile",
  },
  
  -- Window options
  window_options = {
    scrollbind = true,
    cursorbind = false,
    wrap = false,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
