-- Floating editor popup for adding/editing comments.
-- Owns the scratch buffer + floating window lifecycle
local model = require("codediff.comments.model")
local float = require("codediff.ui.lib.float")
local render = require("codediff.ui.comments.render")

local split_lines = model.split_lines

---@class codediff.ui.comments.ActiveEditor
---@field id string
---@field winid integer
---@field bufnr integer
---@field close fun()

---@type codediff.ui.comments.ActiveEditor?
local active_editor = nil

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

---@param key string
---@return string
local function key_label(key)
  local labels = {
    ["<CR>"] = "enter",
    ["<S-CR>"] = "shift+enter",
    ["<S-Enter>"] = "shift+enter",
    ["<S-Return>"] = "shift+enter",
    ["<C-CR>"] = "ctrl+enter",
    ["<C-g>"] = "ctrl+g",
    ["<Esc>"] = "esc",
  }
  if labels[key] then
    return labels[key]
  end
  if type(key) == "string" and key:match("^<.+>$") then
    return key:sub(2, -2):lower()
  end
  return tostring(key)
end

---@param ui codediff.CommentUIOptions
---@return { width: integer, height: integer }
local function get_editor_layout(ui)
  local anchor_win = vim.api.nvim_get_current_win()
  return {
    width = math.min(ui.width, math.max(1, vim.api.nvim_win_get_width(anchor_win) - 2)),
    height = math.min(ui.height, math.max(1, vim.api.nvim_win_get_height(anchor_win) - 2)),
  }
end

local function force_normal_mode()
  pcall(vim.cmd, "stopinsert")
  local mode = vim.api.nvim_get_mode().mode
  if mode:sub(1, 1) == "i" then
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc, "n", false)
  end
end

---@param bufnr integer
---@param submit_keys string[]
---@param cancel_keys string[]
---@param submit_comment fun()
---@param close_editor fun()
---@return { mode: string, key: string }[]
local function apply_editor_keymaps(bufnr, submit_keys, cancel_keys, submit_comment, close_editor)
  local seen = {}
  local applied = {}
  local function map_key(mode, key, cb, group)
    local map_id = string.format("%s:%s:%s", group, mode, key)
    if seen[map_id] then
      return
    end
    seen[map_id] = true
    vim.keymap.set(mode, key, cb, {
      buffer = bufnr,
      noremap = true,
      silent = true,
      nowait = true,
    })
    table.insert(applied, { mode = mode, key = key })
  end
  for _, key in ipairs(submit_keys) do
    if type(key) == "string" and key ~= "" then
      map_key("n", key, submit_comment, "submit")
    end
  end
  for _, key in ipairs(cancel_keys) do
    if type(key) == "string" and key ~= "" then
      map_key("n", key, close_editor, "cancel")
    end
  end
  return applied
end

---@param bufnr integer
---@return string
local function read_editor_text(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return vim.trim(table.concat(lines, "\n"))
end

---@param winid integer
---@param text string?
local function move_editor_cursor_to_end(winid, text)
  local lines = split_lines(text)
  local target_line = math.max(1, #lines)
  local target_text = lines[target_line] or ""
  local target_col = #target_text
  pcall(vim.api.nvim_win_set_cursor, winid, { target_line, target_col })
end

---@param ui codediff.CommentUIOptions
---@return string
local function cancel_hint(ui)
  return ui.cancel_keys[1] or "<Esc>"
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

local M = {}

--- Close the active editor if any.
function M.close_active()
  if active_editor then
    active_editor.close()
  end
end

--- Whether an editor is currently open.
---@return boolean
function M.is_active()
  return active_editor ~= nil
end

--- Open a comment editor popup. Only one can be active at a time.
---@param opts? { title?: string, initial_text?: string, cursor_to_end?: boolean, on_submit?: fun(text: string): boolean }
---@return boolean
function M.open(opts)
  opts = opts or {}
  M.close_active()

  local ui = model.get_ui_options()
  local layout = get_editor_layout(ui)

  local submit_key_hint = ui.submit_keys[1] or "<CR>"
  local cancel_key_hint = cancel_hint(ui)
  local title = string.format(" %s ", opts.title or "CodeDiff Comment")
  local footer = string.format("%s close | %s submit", key_label(cancel_key_hint), key_label(submit_key_hint))

  local previous_win = vim.api.nvim_get_current_win()
  local bufnr = float.create_scratch_buf({ filetype = "markdown" })

  local border = "rounded"
  local win_config = {
    relative = "cursor",
    row = 1,
    col = 0,
    width = layout.width,
    height = layout.height,
    style = "minimal",
    border = border,
    zindex = 220,
  }

  float.apply_title_footer(win_config, border, title, "left", footer, "left")

  local winid = vim.api.nvim_open_win(bufnr, true, win_config)
  float.set_float_win_options(winid, render.winhighlight())
  vim.wo[winid].wrap = true
  vim.wo[winid].linebreak = true
  vim.wo[winid].winblend = ui.opacity

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, split_lines(opts.initial_text))
  if opts.cursor_to_end then
    move_editor_cursor_to_end(winid, opts.initial_text)
  end

  local editor_id = tostring((vim.uv or vim.loop).hrtime())
  local closed = false

  local function close_editor()
    if closed then
      return
    end
    closed = true

    if active_editor and active_editor.id == editor_id then
      active_editor = nil
    end

    vim.schedule(function()
      force_normal_mode()

      if vim.api.nvim_win_is_valid(winid) then
        pcall(vim.api.nvim_win_close, winid, true)
      end

      if vim.api.nvim_win_is_valid(previous_win) then
        pcall(vim.api.nvim_set_current_win, previous_win)
      end

      force_normal_mode()
    end)
  end

  local function submit_comment()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local text = read_editor_text(bufnr)
    if text == "" then
      close_editor()
      return
    end

    local ok_submit = opts.on_submit and opts.on_submit(text)
    if ok_submit then
      close_editor()
    end
  end

  apply_editor_keymaps(bufnr, ui.submit_keys, ui.cancel_keys, submit_comment, close_editor)

  if ui.editor_mode == "insert" then
    vim.cmd("startinsert")
    if opts.cursor_to_end then
      move_editor_cursor_to_end(winid, opts.initial_text)
    end
  end

  active_editor = {
    id = editor_id,
    winid = winid,
    bufnr = bufnr,
    close = close_editor,
  }

  return true
end

--- Reset for tests.
function M._reset_for_tests()
  if active_editor and active_editor.close then
    pcall(active_editor.close)
  end
  active_editor = nil
end

return M
