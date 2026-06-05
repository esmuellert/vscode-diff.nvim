-- Floating help window showing available keymaps (g?)
local config = require("codediff.config")
local lifecycle = require("codediff.ui.lifecycle")

local M = {}

local ns = vim.api.nvim_create_namespace("codediff-help")

-- Key column width (right-aligned keys sit in this space)
local KEY_COL = 14

-- Setup highlight groups for the help window
local function setup_highlights()
  vim.api.nvim_set_hl(0, "CodeDiffHelpHeader", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "CodeDiffHelpSection", { link = "Statement", default = true })
  vim.api.nvim_set_hl(0, "CodeDiffHelpKey", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "CodeDiffHelpSep", { link = "NonText", default = true })
  vim.api.nvim_set_hl(0, "CodeDiffHelpDesc", { link = "Normal", default = true })
end

--- Entry = { key, desc } or nil (skipped)
--- Section = { title, entries[] }

-- Collect a section of keymap entries, skipping nil keys
local function section(title, entries)
  local items = {}
  for _, e in ipairs(entries) do
    if e[1] then
      table.insert(items, e)
    end
  end
  if #items == 0 then
    return nil
  end
  return { title = title, items = items }
end

-- Build sections based on the current session mode
local function build_sections(keymaps, is_explorer, is_history, is_conflict)
  local sections = {}
  local km = keymaps.view

  -- View section
  local view_items = {
    { km.quit, "Close codediff tab" },
    { km.next_hunk, "Next hunk" },
    { km.prev_hunk, "Previous hunk" },
    { km.diff_get, "Get change from other buffer" },
    { km.diff_put, "Put change to other buffer" },
    { km.open_in_prev_tab, "Open buffer in previous tab" },
  }
  if is_explorer or is_history then
    table.insert(view_items, { km.next_file, "Next file" })
    table.insert(view_items, { km.prev_file, "Previous file" })
  end
  if is_explorer then
    table.insert(view_items, { km.toggle_explorer, "Toggle explorer" })
    table.insert(view_items, { km.focus_explorer, "Focus explorer" })
    table.insert(view_items, { km.toggle_stage, "Stage/unstage current file" })
    table.insert(view_items, { km.stage_hunk, "Stage hunk under cursor" })
    table.insert(view_items, { km.unstage_hunk, "Unstage hunk under cursor" })
    table.insert(view_items, { km.discard_hunk, "Discard hunk under cursor" })
  end
  table.insert(view_items, { km.toggle_layout, "Toggle inline/side-by-side layout" })
  if km.align_move then
    table.insert(view_items, { km.align_move, "Align moved code block" })
  end
  table.insert(view_items, { km.toggle_compact, "Toggle compact mode (fold unchanged)" })
  table.insert(view_items, { km.hunk_textobject, "Hunk textobject (visual/operator)" })
  table.insert(view_items, { km.show_help, "Toggle this help" })
  table.insert(sections, section("VIEW", view_items))

  -- Explorer section
  if is_explorer then
    local ekm = keymaps.explorer
    table.insert(
      sections,
      section("EXPLORER", {
        { ekm.select, "Select / toggle expand" },
        { ekm.hover, "Show full path" },
        { ekm.refresh, "Refresh explorer" },
        { ekm.toggle_view_mode, "Toggle list/tree view" },
        { ekm.stage_all, "Stage all files" },
        { ekm.unstage_all, "Unstage all files" },
        { ekm.restore, "Discard changes to file" },
        { ekm.toggle_changes, "Toggle Changes visibility" },
        { ekm.toggle_staged, "Toggle Staged visibility" },
        { ekm.fold_open, "Open fold" },
        { ekm.fold_open_recursive, "Open fold recursively" },
        { ekm.fold_close, "Close fold" },
        { ekm.fold_close_recursive, "Close fold recursively" },
        { ekm.fold_toggle, "Toggle fold" },
        { ekm.fold_toggle_recursive, "Toggle fold recursively" },
        { ekm.fold_open_all, "Open all folds" },
        { ekm.fold_close_all, "Close all folds" },
      })
    )
  end

  -- History section
  if is_history then
    local hkm = keymaps.history
    table.insert(
      sections,
      section("HISTORY", {
        { hkm.select, "Select commit/file or toggle" },
        { hkm.toggle_view_mode, "Toggle list/tree view" },
        { hkm.refresh, "Refresh history" },
        { hkm.fold_open, "Open fold" },
        { hkm.fold_open_recursive, "Open fold recursively" },
        { hkm.fold_close, "Close fold" },
        { hkm.fold_close_recursive, "Close fold recursively" },
        { hkm.fold_toggle, "Toggle fold" },
        { hkm.fold_toggle_recursive, "Toggle fold recursively" },
        { hkm.fold_open_all, "Open all folds" },
        { hkm.fold_close_all, "Close all folds" },
      })
    )
  end

  -- Conflict section
  if is_conflict then
    local ckm = keymaps.conflict
    table.insert(
      sections,
      section("CONFLICT", {
        { ckm.accept_incoming, "Accept incoming (theirs)" },
        { ckm.accept_current, "Accept current (ours)" },
        { ckm.accept_both, "Accept both changes" },
        { ckm.discard, "Discard both (keep base)" },
        { ckm.accept_all_incoming, "Accept ALL incoming" },
        { ckm.accept_all_current, "Accept ALL current" },
        { ckm.accept_all_both, "Accept ALL both" },
        { ckm.discard_all, "Discard ALL (reset to base)" },
        { ckm.next_conflict, "Next conflict" },
        { ckm.prev_conflict, "Previous conflict" },
        { ckm.diffget_incoming, "Get hunk from incoming" },
        { ckm.diffget_current, "Get hunk from current" },
      })
    )
  end

  return sections
end

-- Compute the required window width from sections
local function compute_width(sections)
  local max_desc = 0
  for _, sec in ipairs(sections) do
    for _, item in ipairs(sec.items) do
      max_desc = math.max(max_desc, #item[2])
    end
  end
  -- key_col + " → " (4) + desc + padding
  return math.max(KEY_COL + 4 + max_desc + 3, 40)
end

-- Render sections into the buffer with highlights
-- Returns: lines (string[]), highlights ({ line, col_start, col_end, hl_group }[])
local function render(sections, win_width)
  local lines = {}
  local hls = {}

  for sec_idx, sec in ipairs(sections) do
    if sec_idx > 1 then
      table.insert(lines, "")
    end

    -- Section heading (centered)
    local pad = math.floor((win_width - #sec.title) / 2)
    local heading = string.rep(" ", pad) .. sec.title
    table.insert(lines, heading)
    table.insert(hls, { #lines - 1, pad, pad + #sec.title, "CodeDiffHelpSection" })

    -- Column header
    local col_hdr = string.format("%" .. KEY_COL .. "s    %s", "KEYS", "ACTION")
    table.insert(lines, col_hdr)
    table.insert(hls, { #lines - 1, 0, #col_hdr, "CodeDiffHelpSep" })

    -- Entries
    for _, item in ipairs(sec.items) do
      local key, desc = item[1], item[2]
      local key_str = string.format("%" .. KEY_COL .. "s", key)
      local line = key_str .. " → " .. desc
      table.insert(lines, line)

      local row = #lines - 1
      table.insert(hls, { row, 0, KEY_COL, "CodeDiffHelpKey" })
      table.insert(hls, { row, KEY_COL, KEY_COL + 3, "CodeDiffHelpSep" })
      table.insert(hls, { row, KEY_COL + 3, #line, "CodeDiffHelpDesc" })
    end
  end

  return lines, hls
end

--- Show or toggle the keymap help floating window
function M.toggle(tabpage)
  local session = lifecycle.get_session(tabpage)

  -- Close existing help window if open
  if session and session._help_win and vim.api.nvim_win_is_valid(session._help_win) then
    vim.api.nvim_win_close(session._help_win, true)
    session._help_win = nil
    return
  end

  setup_highlights()

  local keymaps = config.options.keymaps
  local is_explorer = session and session.mode == "explorer"
  local is_history = session and session.mode == "history"
  local is_conflict = session and session.result_bufnr ~= nil

  local sections = build_sections(keymaps, is_explorer, is_history, is_conflict)
  local win_width = compute_width(sections)
  local lines, hls = render(sections, win_width)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "codediff-help"

  -- Apply highlights
  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(buf, ns, hl[4], hl[1], hl[2], hl[3])
  end

  -- Open centered floating window
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - win_width) / 2),
    width = win_width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Keymaps ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = false
  vim.wo[win].winhighlight = "NormalFloat:Normal"

  -- Track window in session for toggle
  if session then
    session._help_win = win
  end

  -- Close keymaps
  local show_help_key = keymaps.view.show_help or "g?"
  for _, key in ipairs({ "q", "<Esc>", show_help_key }) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if session then
        session._help_win = nil
      end
    end, { buffer = buf, nowait = true })
  end
end

return M
