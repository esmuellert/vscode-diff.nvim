-- Highlight setup for diff rendering
local M = {}
local config = require("codediff.config")

-- Namespaces for highlights and fillers
M.ns_highlight = vim.api.nvim_create_namespace("codediff-highlight")
M.ns_filler = vim.api.nvim_create_namespace("codediff-filler")
M.ns_conflict = vim.api.nvim_create_namespace("codediff-conflict")

-- Helper function to adjust color brightness
local function adjust_brightness(color, factor)
  if not color then
    return nil
  end
  local r = math.floor(color / 65536) % 256
  local g = math.floor(color / 256) % 256
  local b = color % 256

  -- Apply factor and clamp to 0-255
  r = math.min(255, math.floor(r * factor))
  g = math.min(255, math.floor(g * factor))
  b = math.min(255, math.floor(b * factor))

  return r * 65536 + g * 256 + b
end

-- Read the effective background color of a highlight group as Neovim's renderer
-- would resolve it. Some colorschemes (e.g. built-in `sorbet`) define DiffAdd /
-- DiffDelete using `fg` plus `reverse = true`; Neovim's renderer swaps fg<->bg
-- at draw time, so the visually-correct "background" comes from `fg`. Just
-- reading `hl.bg` produces black/default for those schemes (issue #366).
-- Returns gui_bg, cterm_bg (either may be nil if neither side is defined).
local function effective_bg(hl)
  if not hl then
    return nil, nil
  end
  local gui = (hl.reverse and hl.fg) or hl.bg
  local cterm_reverse = (hl.cterm and hl.cterm.reverse) or hl.reverse
  local cterm = (cterm_reverse and hl.ctermfg) or hl.ctermbg
  return gui, cterm
end

-- Resolve color from config value (supports highlight group name or direct color)
-- Returns a table suitable for nvim_set_hl (e.g., { bg = 0x2ea043 })
local function resolve_color(value, fallback_gui, fallback_cterm)
  if not value then
    return { bg = fallback_gui, ctermbg = fallback_cterm }
  end

  -- If it's a string, check if it's a hex color or highlight group name
  if type(value) == "string" then
    -- Check if it's a hex color (#RRGGBB or #RGB)
    if value:match("^#%x%x%x%x%x%x$") then
      -- #RRGGBB format
      local r = tonumber(value:sub(2, 3), 16)
      local g = tonumber(value:sub(4, 5), 16)
      local b = tonumber(value:sub(6, 7), 16)
      return {
        bg = r * 65536 + g * 256 + b,
        ctermbg = fallback_cterm,
      }
    elseif value:match("^#%x%x%x$") then
      -- #RGB format - expand to #RRGGBB
      local r = tonumber(value:sub(2, 2), 16) * 17
      local g = tonumber(value:sub(3, 3), 16) * 17
      local b = tonumber(value:sub(4, 4), 16) * 17
      return {
        bg = r * 65536 + g * 256 + b,
        ctermbg = fallback_cterm,
      }
    else
      -- Assume it's a highlight group name
      local hl = vim.api.nvim_get_hl(0, { name = value, link = false })
      local gui, cterm = effective_bg(hl)
      return {
        bg = gui or fallback_gui,
        ctermbg = cterm or fallback_cterm,
      }
    end
  elseif type(value) == "number" then
    -- Direct color number (e.g., 0x2ea043 or a base256 index)
    return { bg = value, ctermbg = value }
  end

  return { bg = fallback_gui, ctermbg = fallback_cterm }
end

local function is_highlight_group(value)
  return type(value) == "string" and not value:match("^#%x%x%x%x%x%x$") and not value:match("^#%x%x%x$")
end

local function effective_colors(fg, bg, reverse, fallback_bg)
  if reverse then
    return bg, fg or fallback_bg
  end
  return fg, bg or fallback_bg
end

-- Unlike line highlights, configured character groups retain all attributes; fallbacks only fill missing backgrounds.
local function resolve_char_highlight(configured_value, fallback_bg, fallback_cterm_bg)
  if not is_highlight_group(configured_value) then
    return resolve_color(configured_value, fallback_bg, fallback_cterm_bg)
  end

  local source = vim.api.nvim_get_hl(0, { name = configured_value, link = false })
  local result = vim.deepcopy(source)
  local cterm_reverse = (source.cterm and source.cterm.reverse) or source.reverse

  result.fg, result.bg = effective_colors(source.fg, source.bg, source.reverse, fallback_bg)
  result.ctermfg, result.ctermbg = effective_colors(source.ctermfg, source.ctermbg, cterm_reverse, fallback_cterm_bg)

  result.reverse = nil
  if result.cterm then
    result.cterm.reverse = nil
  end

  return result
end

-- Returns the base 256 color palette index of rgb color cube where r, g, b are 0-5 inclusive.
local function base256_color(r, g, b)
  return 16 + r * 36 + g * 6 + b
end

-- Returns the base 256 color palette index of greyscale shade where the shade is 0-23 inclusive.
local function base256_greyscale(shade)
  return 232 + shade
end

-- Setup VSCode-style highlight groups
function M.setup()
  local opts = config.options.highlights

  -- Line-level highlights
  local line_insert_color = resolve_color(opts.line_insert, 0x1d3042, base256_color(0, 1, 0))
  local line_delete_color = resolve_color(opts.line_delete, 0x351d2b, base256_color(1, 0, 0))

  vim.api.nvim_set_hl(0, "CodeDiffLineInsert", line_insert_color)
  vim.api.nvim_set_hl(0, "CodeDiffLineDelete", line_delete_color)

  -- Character-level highlights: use explicit values if provided, otherwise derive from line highlights
  local char_insert_color
  local char_delete_color

  -- Auto-detect brightness based on background if not explicitly set
  local brightness = opts.char_brightness or (vim.o.background == "light" and 0.92 or 1.4)

  if opts.char_insert then
    -- Explicit char_insert provided - use it directly
    char_insert_color = resolve_char_highlight(opts.char_insert, 0x2a4556, base256_color(0, 2, 0))
  else
    -- Derive from line_insert with brightness adjustment
    char_insert_color = {
      bg = adjust_brightness(line_insert_color.bg, brightness) or 0x2a4556,
      ctermbg = base256_color(0, 2, 0),
    }
  end

  if opts.char_delete then
    -- Explicit char_delete provided - use it directly
    char_delete_color = resolve_char_highlight(opts.char_delete, 0x4b2a3d, base256_color(2, 0, 0))
  else
    -- Derive from line_delete with brightness adjustment
    char_delete_color = {
      bg = adjust_brightness(line_delete_color.bg, brightness) or 0x4b2a3d,
      ctermbg = base256_color(2, 0, 0),
    }
  end

  vim.api.nvim_set_hl(0, "CodeDiffCharInsert", char_insert_color)
  vim.api.nvim_set_hl(0, "CodeDiffCharDelete", char_delete_color)

  vim.api.nvim_set_hl(0, "CodeDiffGutterInsert", { link = "CodeDiffLineInsert", default = true })
  vim.api.nvim_set_hl(0, "CodeDiffGutterDelete", { link = "CodeDiffLineDelete", default = true })

  -- Neovim applies number_hl_group to virtual lines anchored to the same buffer line.
  -- Keep these groups foreground-only so filler rows do not inherit a colored number-column background.
  vim.api.nvim_set_hl(0, "CodeDiffGutterInsertNumber", {
    fg = char_insert_color.bg,
    ctermfg = char_insert_color.ctermbg,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodeDiffGutterDeleteNumber", {
    fg = char_delete_color.bg,
    ctermfg = char_delete_color.ctermbg,
    default = true,
  })

  -- Moved code highlights (derived from DiffChange — the standard "changed" color)
  local diff_change_hl = vim.api.nvim_get_hl(0, { name = "DiffChange", link = false })
  local move_fallback = effective_bg(diff_change_hl) or 0x4f5258
  local line_move_color = resolve_color(opts.line_move, move_fallback, base256_color(0, 0, 2))
  vim.api.nvim_set_hl(0, "CodeDiffLineMove", line_move_color)

  local char_move_color = {
    bg = adjust_brightness(line_move_color.bg, brightness) or 0x2a4f7a,
    ctermbg = base256_color(0, 0, 3),
  }
  vim.api.nvim_set_hl(0, "CodeDiffCharMove", char_move_color)

  vim.api.nvim_set_hl(0, "CodeDiffMoveFrom", {
    fg = 0x6699cc,
    ctermfg = base256_color(1, 2, 4),
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodeDiffMoveTo", {
    fg = 0x6699cc,
    ctermfg = base256_color(1, 2, 4),
    default = true,
  })

  -- Filler lines (no highlight, inherits editor default background)
  vim.api.nvim_set_hl(0, "CodeDiffFiller", {
    fg = "#444444", -- Subtle gray for the slash character
    ctermfg = base256_greyscale(8),
    default = true,
  })

  -- Explorer directory text (smaller and dimmed)
  vim.api.nvim_set_hl(0, "ExplorerDirectorySmall", {
    link = "Comment",
    default = true,
  })

  -- Explorer selected file
  vim.api.nvim_set_hl(0, "CodeDiffExplorerSelected", {
    link = "Visual",
    default = true,
  })

  -- Explorer indent markers (tree view)
  vim.api.nvim_set_hl(0, "NeoTreeIndentMarker", {
    link = "Comment",
    default = true,
  })

  vim.api.nvim_set_hl(0, "CodeDiffExplorerTreeGroup", {
    link = "Directory",
    default = true,
  })

  -- Explorer git status highlights (customizable, like diffview.nvim)
  vim.api.nvim_set_hl(0, "CodeDiffStatusAdded", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "CodeDiffStatusModified", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "CodeDiffStatusDeleted", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "CodeDiffStatusRenamed", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "CodeDiffStatusUntracked", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "CodeDiffStatusConflict", { link = "DiagnosticError", default = true })

  -- Helper to check if a highlight group exists and has foreground color
  local function hl_exists(name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
    return ok and hl and (hl.fg or hl.foreground)
  end

  -- Helper to set conflict sign highlight with user config as priority 0
  -- @param hl_name string The highlight group name to set
  -- @param user_value string|nil User config value (highlight group or hex color)
  -- @param fallbacks table List of fallback highlight groups to try
  -- @param default_hex string Default hex color if all fallbacks fail
  local function set_conflict_sign_hl(hl_name, user_value, fallbacks, default_hex)
    -- Priority 0: User config
    if user_value then
      if user_value:match("^#%x%x%x%x%x%x$") then
        -- Hex color
        vim.api.nvim_set_hl(0, hl_name, { fg = user_value, default = true })
      else
        -- Highlight group name
        vim.api.nvim_set_hl(0, hl_name, { link = user_value, default = true })
      end
      return
    end

    -- Try fallback chain
    for _, fallback in ipairs(fallbacks) do
      if hl_exists(fallback) then
        vim.api.nvim_set_hl(0, hl_name, { link = fallback, default = true })
        return
      end
    end

    -- Final fallback: hardcoded hex
    vim.api.nvim_set_hl(0, hl_name, { fg = default_hex, default = true })
  end

  local hl_config = config.options.highlights

  -- Conflict sign in gutter (for merge view) - unresolved conflicts
  -- Fallback chain: user config -> DiagnosticSignWarn -> hardcoded orange
  set_conflict_sign_hl("CodeDiffConflictSign", hl_config.conflict_sign, { "DiagnosticSignWarn" }, "#f0883e")

  -- Conflict sign in gutter (for merge view) - resolved conflicts (generic)
  -- Fallback chain: user config -> Comment -> hardcoded gray
  set_conflict_sign_hl("CodeDiffConflictSignResolved", hl_config.conflict_sign_resolved, { "Comment" }, "#6e7681")

  -- Conflict sign for accepted side (green - this content was chosen)
  -- Fallback chain: user config -> GitSignsAdd -> DiagnosticSignOk -> hardcoded green
  set_conflict_sign_hl("CodeDiffConflictSignAccepted", hl_config.conflict_sign_accepted, { "GitSignsAdd", "DiagnosticSignOk" }, "#3fb950")

  -- Conflict sign for rejected side (red - this content was not chosen)
  -- Fallback chain: user config -> GitSignsDelete -> DiagnosticSignError -> hardcoded red
  set_conflict_sign_hl("CodeDiffConflictSignRejected", hl_config.conflict_sign_rejected, { "GitSignsDelete", "DiagnosticSignError" }, "#f85149")

  -- History panel title (bold, slightly dimmed)
  vim.api.nvim_set_hl(0, "CodeDiffHistoryTitle", {
    bold = true,
    link = "FloatTitle",
    default = true,
  })

  -- Re-derive when the user switches colorscheme at runtime. Without this, the
  -- CodeDiffLineInsert/Delete colors are frozen to whatever scheme was active
  -- at first setup() and look wrong under any later :colorscheme change.
  if not M._colorscheme_autocmd_installed then
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("codediff_highlights", { clear = true }),
      callback = function()
        M.setup()
      end,
    })
    M._colorscheme_autocmd_installed = true
  end
end

return M
