-- Render module: owns all extmark and popup rendering for comments.
-- Maintains a parallel state of UI handles separate from the store's domain data.
local M = {}

local model = require("codediff.comments.model")
local float = require("codediff.ui.lib.float")
local config = require("codediff.config")

local SIDE = model.SIDE
local split_lines = model.split_lines
local truncate_text = model.truncate_text

local ns = vim.api.nvim_create_namespace("codediff-comments")

---@class codediff.ui.comments.Handle
---@field bufnr integer Buffer the extmark is placed in
---@field extmark_id integer
---@field popup_winid? integer
---@field popup_bufnr? integer

--- handles[tabpage][comment_id] = Handle
---@type table<integer, table<integer, codediff.ui.comments.Handle>>
local handles = {}

-- ---------------------------------------------------------------------------
-- Highlights
-- ---------------------------------------------------------------------------

local DEFAULT_BORDER_FG = 0xA6ADC8

local function setup_comment_highlights()
  local border_fg = DEFAULT_BORDER_FG
  local border_bg = "NONE"
  local ok_hl, normal_hl = pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
  if ok_hl and normal_hl then
    if type(normal_hl.fg) == "number" then
      border_fg = normal_hl.fg
    end
    if type(normal_hl.bg) == "number" then
      border_bg = normal_hl.bg
    end
  end

  local meta_fg = border_fg
  local ok_comment_hl, comment_hl = pcall(vim.api.nvim_get_hl, 0, { name = "Comment", link = false })
  if ok_comment_hl and comment_hl and type(comment_hl.fg) == "number" then
    meta_fg = comment_hl.fg
  end

  vim.api.nvim_set_hl(0, "CodeDiffCommentBorder", { fg = border_fg, bg = border_bg })
  vim.api.nvim_set_hl(0, "CodeDiffCommentMeta", { fg = meta_fg, bg = border_bg })
end

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

---@return string
local function comment_winhighlight()
  return "NormalFloat:NormalFloat,FloatBorder:CodeDiffCommentBorder,FloatTitle:CodeDiffCommentMeta,FloatFooter:CodeDiffCommentMeta"
end

---@return string?
local function comment_hint_text()
  local keymaps = (config.options.keymaps or {}).view or {}
  local hint_parts = {}
  if keymaps.comment_edit then
    table.insert(hint_parts, "edit " .. keymaps.comment_edit)
  end
  if keymaps.comment_remove then
    table.insert(hint_parts, "delete " .. keymaps.comment_remove)
  end
  if #hint_parts == 0 then
    return nil
  end
  return table.concat(hint_parts, " | ")
end

---@param tabpage integer
---@param bufnr integer
---@return integer?
local function find_window_for_buffer(tabpage, bufnr)
  if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then
    return nil
  end
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      return winid
    end
  end
  return nil
end

---@param comment codediff.comments.Comment
---@param session table
---@return boolean
local function comment_visible_in_session(comment, session)
  local side_meta = SIDE[comment.side]
  local active_path = side_meta and session[side_meta.path_key] or nil
  if type(active_path) ~= "string" or active_path == "" then
    return false
  end
  return comment.path == active_path
end

---@param tabpage integer
---@return table<integer, codediff.ui.comments.Handle>
local function get_tab_handles(tabpage)
  if not handles[tabpage] then
    handles[tabpage] = {}
  end
  return handles[tabpage]
end

-- ---------------------------------------------------------------------------
-- Handle lifecycle
-- ---------------------------------------------------------------------------

---@param handle codediff.ui.comments.Handle
local function close_handle(handle)
  if handle.popup_winid and vim.api.nvim_win_is_valid(handle.popup_winid) then
    pcall(vim.api.nvim_win_close, handle.popup_winid, true)
  end
  handle.popup_winid = nil

  if handle.popup_bufnr and vim.api.nvim_buf_is_valid(handle.popup_bufnr) then
    pcall(vim.api.nvim_buf_delete, handle.popup_bufnr, { force = true })
  end
  handle.popup_bufnr = nil

  if handle.extmark_id and vim.api.nvim_buf_is_valid(handle.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, handle.bufnr, ns, handle.extmark_id)
  end
end

---@param tabpage integer
---@param comment_id integer
local function clear_handle(tabpage, comment_id)
  local tab = handles[tabpage]
  if not tab then
    return
  end
  local handle = tab[comment_id]
  if not handle then
    return
  end
  close_handle(handle)
  tab[comment_id] = nil
end

-- ---------------------------------------------------------------------------
-- Popup rendering
-- ---------------------------------------------------------------------------

---@param tabpage integer
---@param comment codediff.comments.Comment
---@param handle codediff.ui.comments.Handle
---@param comments codediff.comments.Comment[]
---@param session table
---@return boolean
local function render_comment_popup(tabpage, comment, handle, comments, session)
  if not vim.api.nvim_buf_is_valid(handle.bufnr) then
    return false
  end

  local anchor_win = find_window_for_buffer(tabpage, handle.bufnr)
  if not anchor_win then
    if handle.popup_winid and vim.api.nvim_win_is_valid(handle.popup_winid) then
      pcall(vim.api.nvim_win_close, handle.popup_winid, true)
    end
    handle.popup_winid = nil
    return true
  end

  local ui = model.get_ui_options()
  local hint = comment_hint_text()
  local lines = split_lines(comment.text)

  local max_line_width = 0
  for _, line in ipairs(lines) do
    max_line_width = math.max(max_line_width, vim.fn.strdisplaywidth(line))
  end
  if max_line_width == 0 then
    max_line_width = 1
  end

  local win_width = vim.api.nvim_win_get_width(anchor_win)
  local max_popup_width = math.max(24, math.floor(win_width * 0.52))
  local hint_width = hint and vim.fn.strdisplaywidth(hint) or 0
  local content_width = math.min(math.max(max_line_width, hint_width), max_popup_width)

  local display_lines = {}
  for _, line in ipairs(lines) do
    table.insert(display_lines, truncate_text(line, content_width))
  end

  -- Compute stack offset from handles on the same line with lower id.
  local stack_offset = 0
  local tab = handles[tabpage] or {}
  for _, candidate in ipairs(comments) do
    if
      candidate.id ~= comment.id
      and candidate.side == comment.side
      and candidate.path == comment.path
      and candidate.line == comment.line
      and candidate.id < comment.id
      and comment_visible_in_session(candidate, session)
      and tab[candidate.id]
    then
      stack_offset = stack_offset + 1
    end
  end

  local popup_bufnr = handle.popup_bufnr
  if not popup_bufnr or not vim.api.nvim_buf_is_valid(popup_bufnr) then
    popup_bufnr = float.create_scratch_buf()
    handle.popup_bufnr = popup_bufnr
  end

  local win_config = {
    relative = "win",
    win = anchor_win,
    bufpos = { comment.line - 1, 0 },
    row = stack_offset,
    col = math.max(2, win_width - content_width - 6),
    width = content_width,
    height = math.max(1, #display_lines),
    style = "minimal",
    focusable = false,
    zindex = 210,
    noautocmd = true,
  }

  local border = "rounded"
  win_config.border = border

  float.apply_title_footer(win_config, border, string.format(" c%d ", comment.id), "left", hint or nil, "left")

  local popup_winid = float.open_or_reconfigure(handle.popup_winid, popup_bufnr, false, win_config)
  handle.popup_winid = popup_winid

  vim.bo[popup_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(popup_bufnr, 0, -1, false, display_lines)
  vim.bo[popup_bufnr].modifiable = false

  float.set_float_win_options(popup_winid, comment_winhighlight())
  vim.wo[popup_winid].winblend = ui.opacity

  return true
end

-- ---------------------------------------------------------------------------
-- Extmark rendering
-- ---------------------------------------------------------------------------

---@param comment codediff.comments.Comment
---@param handle codediff.ui.comments.Handle
---@return boolean
local function render_extmark(comment, handle)
  if not vim.api.nvim_buf_is_valid(handle.bufnr) then
    return false
  end

  local extmark_opts = {
    sign_text = "C",
    sign_hl_group = "DiagnosticSignInfo",
    number_hl_group = "DiagnosticSignInfo",
    priority = 220,
  }

  if handle.extmark_id and handle.extmark_id ~= 0 then
    extmark_opts.id = handle.extmark_id
  end

  if comment.end_line and comment.end_line > comment.line then
    local buf_line_count = vim.api.nvim_buf_line_count(handle.bufnr)
    local clamped_end = math.min(comment.end_line, buf_line_count)
    extmark_opts.end_row = clamped_end - 1
    extmark_opts.end_col = 0
  end

  local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, handle.bufnr, ns, comment.line - 1, 0, extmark_opts)
  if not ok then
    return false
  end

  handle.extmark_id = extmark_id
  return true
end

-- ---------------------------------------------------------------------------
-- Position sync
-- ---------------------------------------------------------------------------

---@param handle codediff.ui.comments.Handle
---@return { line: integer, end_line: integer? }?
local function sync_handle_position(handle)
  if not vim.api.nvim_buf_is_valid(handle.bufnr) then
    return nil
  end
  if not handle.extmark_id then
    return nil
  end

  local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, handle.bufnr, ns, handle.extmark_id, { details = true })
  if not ok or not pos or #pos == 0 then
    return nil
  end

  local result = { line = pos[1] + 1 }
  local details = pos[3]
  if details and details.end_row then
    result.end_line = details.end_row + 1
  end

  return result
end

-- ---------------------------------------------------------------------------
-- Popup visibility helpers
-- ---------------------------------------------------------------------------

local function hide_popup(handle)
  if handle.popup_winid and vim.api.nvim_win_is_valid(handle.popup_winid) then
    pcall(vim.api.nvim_win_close, handle.popup_winid, true)
  end
  handle.popup_winid = nil
end

-- ---------------------------------------------------------------------------
-- Per-comment helpers (used by reconcile / capture_position_patches)
-- ---------------------------------------------------------------------------

---@param tabpage integer
---@param session table
---@param comment codediff.comments.Comment
---@param comments codediff.comments.Comment[]
---@param tab table<integer, codediff.ui.comments.Handle>
local function reconcile_comment(tabpage, session, comment, comments, tab)
  if not comment_visible_in_session(comment, session) then
    if tab[comment.id] then
      clear_handle(tabpage, comment.id)
    end
    return
  end

  local target_bufnr = M.resolve_bufnr(session, comment)
  if not target_bufnr then
    if tab[comment.id] then
      clear_handle(tabpage, comment.id)
    end
    return
  end

  local handle = tab[comment.id]

  if handle and handle.bufnr ~= target_bufnr then
    clear_handle(tabpage, comment.id)
    handle = nil
  end

  local is_new = not handle
  if not handle then
    ---@type codediff.ui.comments.Handle
    handle = { bufnr = target_bufnr, extmark_id = 0 }
    tab[comment.id] = handle
  end

  -- Invalidate existing popup so it re-renders with fresh content (e.g. after edit).
  if not is_new then
    hide_popup(handle)
  end

  if handle.extmark_id ~= 0 then
    local pos = sync_handle_position(handle)
    if not pos then
      handle.extmark_id = 0
      if not render_extmark(comment, handle) then
        clear_handle(tabpage, comment.id)
        return
      end
    end
  else
    if not render_extmark(comment, handle) then
      clear_handle(tabpage, comment.id)
      return
    end
  end

  local sticky = model.is_sticky()

  if sticky then
    local cmt = comment
    local hdl = handle
    vim.schedule(function()
      if not hdl.extmark_id or hdl.extmark_id == 0 then
        return
      end
      render_comment_popup(tabpage, cmt, hdl, comments, session)
    end)
  end
end

---@param comment codediff.comments.Comment
---@param handle codediff.ui.comments.Handle?
---@param session table
---@param updates { id: integer, changes: codediff.comments.CommentPatch }[]
---@param stale_ids integer[]
local function capture_comment_patch(comment, handle, session, updates, stale_ids)
  if not comment_visible_in_session(comment, session) then
    return
  end

  if not handle or not handle.extmark_id or handle.extmark_id == 0 then
    stale_ids[#stale_ids + 1] = comment.id
    return
  end

  local pos = sync_handle_position(handle)
  if not pos then
    stale_ids[#stale_ids + 1] = comment.id
    return
  end

  local changed = false
  ---@type codediff.comments.CommentPatch
  local patch = {}
  if pos.line ~= comment.line then
    patch.line = pos.line
    changed = true
  end
  if comment.end_line then
    if pos.end_line and pos.end_line ~= comment.end_line then
      patch.end_line = pos.end_line
      changed = true
    elseif not pos.end_line then
      patch.end_line = false
      changed = true
    end
  end
  if changed then
    updates[#updates + 1] = { id = comment.id, changes = patch }
  end
end

-- ---------------------------------------------------------------------------
-- Non-sticky helpers: show popup only when cursor is on a commented line
-- ---------------------------------------------------------------------------

--- Hide all popups for a tab (used on BufLeave / WinLeave).
---@param tabpage integer
function M.hide_all_popups(tabpage)
  local tab = handles[tabpage]
  if not tab then
    return
  end
  for _, handle in pairs(tab) do
    hide_popup(handle)
  end
end

--- Update popup visibility for non-sticky mode based on the viewport.
--- Shows popups for comments whose line is visible on screen, hides the rest.
---@param tabpage integer
---@param session table
---@param comments codediff.comments.Comment[]
function M.update_viewport_popups(tabpage, session, comments)
  local tab = handles[tabpage]
  if not tab then
    return
  end

  -- Build a set of visible ranges per buffer from the tab's windows.
  ---@type table<integer, { top: integer, bot: integer }[]>
  local visible = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_win_is_valid(winid) then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local top = vim.fn.line("w0", winid)
      local bot = vim.fn.line("w$", winid)
      if not visible[bufnr] then
        visible[bufnr] = {}
      end
      table.insert(visible[bufnr], { top = top, bot = bot })
    end
  end

  for _, comment in ipairs(comments) do
    local handle = tab[comment.id]
    if not handle then
      goto continue
    end

    local in_view = false
    local ranges = visible[handle.bufnr]
    if ranges then
      local cline = comment.line
      for _, r in ipairs(ranges) do
        if cline >= r.top and cline <= r.bot then
          in_view = true
          break
        end
      end
    end

    if in_view then
      if not handle.popup_winid or not vim.api.nvim_win_is_valid(handle.popup_winid) then
        render_comment_popup(tabpage, comment, handle, comments, session)
      end
    else
      hide_popup(handle)
    end

    ::continue::
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Initialize highlights. Call once during setup.
function M.setup()
  setup_comment_highlights()
end

--- Reapply highlights after colorscheme change.
function M.refresh_highlights()
  setup_comment_highlights()
end

--- Get the winhighlight string for comment floats (used by editor too).
---@return string
function M.winhighlight()
  return comment_winhighlight()
end

--- Resolve which buffer a comment should render in for the current session.
--- Returns nil if the comment is not visible.
---@param session table
---@param comment codediff.comments.Comment
---@return integer? bufnr
function M.resolve_bufnr(session, comment)
  if not comment_visible_in_session(comment, session) then
    return nil
  end
  local side_meta = SIDE[comment.side]
  local target_bufnr = side_meta and session[side_meta.bufnr_key] or nil
  if not target_bufnr or not vim.api.nvim_buf_is_valid(target_bufnr) then
    return nil
  end
  return target_bufnr
end

--- Reconcile rendered state for a tab. Shows/hides/updates extmarks+popups
--- based on which comments are visible in the current session.
--- This is called on scroll/resize autocmds and after mutations.
---@param tabpage integer
---@param session table The lifecycle session object
---@param comments codediff.comments.Comment[] Current snapshot from store
function M.reconcile(tabpage, session, comments)
  local tab = get_tab_handles(tabpage)
  local live_ids = {}

  for _, comment in ipairs(comments) do
    live_ids[comment.id] = true
    reconcile_comment(tabpage, session, comment, comments, tab)
  end

  for id, _ in pairs(tab) do
    if not live_ids[id] then
      clear_handle(tabpage, id)
    end
  end
end

--- Capture position updates from extmarks. Returns pure data for the facade
--- to feed back into the store. Does NOT mutate the store.
---@param tabpage integer
---@param session table
---@param comments codediff.comments.Comment[]
---@return { updates: { id: integer, changes: codediff.comments.CommentPatch }[], stale_ids: integer[] }
function M.capture_position_patches(tabpage, session, comments)
  local tab = handles[tabpage] or {}
  local updates = {}
  local stale_ids = {}

  for _, comment in ipairs(comments) do
    capture_comment_patch(comment, tab[comment.id], session, updates, stale_ids)
  end

  return { updates = updates, stale_ids = stale_ids }
end

--- Clear all UI handles for a tab.
---@param tabpage integer
function M.clear_tab(tabpage)
  local tab = handles[tabpage]
  if not tab then
    return
  end
  for id, _ in pairs(tab) do
    clear_handle(tabpage, id)
  end
  handles[tabpage] = nil
end

--- Clear all UI handles for all tabs.
function M.clear_all()
  for tabpage, _ in pairs(handles) do
    M.clear_tab(tabpage)
  end
  handles = {}
end

--- Reset for tests.
function M._reset_for_tests()
  M.clear_all()
end

return M
