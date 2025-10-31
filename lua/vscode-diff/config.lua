-- Configuration module
local M = {}

M.defaults = {
  -- Highlight configuration
  highlights = {
    -- Base highlight groups to derive colors from
    line_insert = "DiffAdd",      -- Line-level insertions (base color)
    line_delete = "DiffDelete",   -- Line-level deletions (base color)

    -- Character-level highlights use brighter versions of line highlights
    char_brightness = 1.4,  -- Multiplier for character backgrounds (1.3 = 130% = brighter)
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
