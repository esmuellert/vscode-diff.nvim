-- Builds and opens quickfix lists for pending comments.
-- Uses custom navigation to jump to the correct CodeDiff diff pane
-- instead of Neovim's default quickfix buffer-opening behavior.
local model = require("codediff.comments.model")

local SIDE = model.SIDE
local split_lines = model.split_lines
local truncate_text = model.truncate_text
local format_line_ref = model.format_line_ref
local sorted_comments = model.sorted_comments
local relative_path = model.relative_path
local store = require("codediff.comments.store")

---@type fun()? Active store subscription unsubscribe function
local active_unsub = nil

---@param path string
---@return boolean
local function is_absolute_path(path)
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

---@param comment codediff.comments.Comment
---@param session table?
---@return string?
local function quickfix_filename_for_comment(comment, session)
  local path = comment.path
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 1) == "(" and path:sub(-1) == ")" then
    return nil
  end
  if is_absolute_path(path) then
    return path
  end
  if session and type(session.git_root) == "string" and session.git_root ~= "" then
    return session.git_root .. "/" .. path
  end
  return path
end

---@param comments codediff.comments.Comment[]
---@param session table?
---@return table[]
local function build_quickfix_items(comments, session)
  local items = {}
  for _, comment in ipairs(sorted_comments(comments)) do
    local lines = split_lines(comment.text)
    local line = tonumber(comment.line) or 1
    local line_ref = format_line_ref(comment)
    local item = {
      lnum = math.max(1, line),
      col = 1,
      type = "I",
      text = string.format("c%d [%s] %s:%s %s", comment.id, tostring(comment.side or "?"), tostring(comment.path or ""), line_ref, truncate_text(lines[1] or "", 120)),
    }
    -- Use filename only (never bufnr) so Neovim doesn't open the diff buffer
    -- in a wrong window. Custom <CR> handler navigates to the correct pane.
    local filename = quickfix_filename_for_comment(comment, session)
    if filename then
      item.filename = filename
    end
    table.insert(items, item)
  end
  return items
end

--- Parse comment ID from a quickfix item text field.
---@param text string
---@return integer?
local function parse_comment_id(text)
  local id = text:match("c(%d+) ")
  return id and tonumber(id) or nil
end

---@param explorer table
---@param path string
---@return table?, string?
local function find_file_in_explorer(explorer, path)
  local sr = explorer and explorer.status_result
  if not sr then
    return nil, nil
  end
  local groups = { "conflicts", "unstaged", "staged" }
  for _, group in ipairs(groups) do
    for _, f in ipairs(sr[group] or {}) do
      if f.path == path then
        -- Ensure the returned data has the group field set,
        -- since status_result entries don't include it but
        -- explorer.on_file_select needs it for tree highlighting.
        local data = vim.deepcopy(f)
        data.group = group
        return data, group
      end
    end
  end
  return nil, nil
end

---@param session table
---@param comment_path string
---@return boolean
local function session_shows_path(session, comment_path)
  if not session or not comment_path then
    return false
  end
  local git_root = session.git_root
  local norm_comment = relative_path(comment_path, git_root)
  local norm_orig = relative_path(session.original_path or "", git_root)
  local norm_mod = relative_path(session.modified_path or "", git_root)
  return norm_comment == norm_orig or norm_comment == norm_mod
end

---@param tabpage integer
---@param comment_id integer
---@param side_meta table
local function jump_to_comment_line(tabpage, comment_id, side_meta)
  local lifecycle = require("codediff.ui.lifecycle")
  local render = require("codediff.ui.comments.render")

  local session = lifecycle.get_session(tabpage)
  if not session then
    return
  end
  local comment = store.get(tabpage, comment_id)
  if not comment then
    return
  end

  local target_win = session[side_meta.bufnr_key == "original_bufnr" and "original_win" or "modified_win"]
  if not target_win or not vim.api.nvim_win_is_valid(target_win) then
    return
  end

  vim.api.nvim_set_current_win(target_win)
  local line = math.max(1, comment.line)
  local buf_lines = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(target_win))
  line = math.min(line, buf_lines)
  vim.api.nvim_win_set_cursor(target_win, { line, 0 })
  vim.cmd("normal! zz")

  render.reconcile(tabpage, session, store.list(tabpage))
end

--- Navigate to the correct CodeDiff diff pane for a comment.
--- Focuses the diff window and positions the cursor on the comment line.
--- If the comment's file is not currently displayed, switches the diff view
--- via the explorer's on_file_select before jumping.
---@param comment_id integer
---@return boolean
local function navigate_to_comment(comment_id)
  local lifecycle = require("codediff.ui.lifecycle")

  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local session = lifecycle.get_session(tabpage)
    if not session then
      goto next_tab
    end

    local comments = store.list(tabpage)
    for _, comment in ipairs(comments) do
      if comment.id == comment_id then
        local side_meta = SIDE[comment.side]
        if not side_meta then
          return false
        end

        -- Switch to the tabpage if needed
        if vim.api.nvim_get_current_tabpage() ~= tabpage then
          vim.api.nvim_set_current_tabpage(tabpage)
        end

        -- Check if the session is already showing this file
        if session_shows_path(session, comment.path) then
          -- Same file — just jump to the line
          jump_to_comment_line(tabpage, comment_id, side_meta)
          return true
        end

        -- Different file — use the explorer to switch
        local explorer = lifecycle.get_explorer(tabpage)
        if not explorer or not explorer.on_file_select then
          -- No explorer available, fall back to direct jump
          jump_to_comment_line(tabpage, comment_id, side_meta)
          return true
        end

        -- Normalize comment path to relative (explorer uses relative paths)
        local lookup_path = relative_path(comment.path, session.git_root)
        local file_data, _ = find_file_in_explorer(explorer, lookup_path)
        if not file_data then
          -- File not found in explorer status, fall back to direct jump
          jump_to_comment_line(tabpage, comment_id, side_meta)
          return true
        end

        -- Trigger file selection (this calls view.update via vim.schedule internally)
        explorer.on_file_select(file_data)

        -- Wait for the view to switch to the new file before jumping to line.
        -- on_file_select schedules view.update asynchronously (and may involve
        -- git operations), so we poll until the session path matches.
        local target_path = relative_path(comment.path, session.git_root)
        local attempts = 0
        local max_attempts = 20 -- ~1s max
        local function try_jump()
          attempts = attempts + 1
          local updated_session = lifecycle.get_session(tabpage)
          if updated_session and session_shows_path(updated_session, target_path) then
            jump_to_comment_line(tabpage, comment_id, side_meta)
            return
          end
          if attempts < max_attempts then
            vim.defer_fn(try_jump, 50)
          end
        end
        vim.defer_fn(try_jump, 50)

        return true
      end
    end
    ::next_tab::
  end

  return false
end

--- Custom <CR> handler for the quickfix window.
local function on_quickfix_select()
  local line = vim.api.nvim_get_current_line()
  local comment_id = parse_comment_id(line:match("|(.*)$") or line)
  if not comment_id then
    -- Fallback to default behavior
    vim.cmd("cc " .. vim.fn.line("."))
    return
  end

  if not navigate_to_comment(comment_id) then
    -- Comment no longer exists or session closed; fallback
    vim.cmd("cc " .. vim.fn.line("."))
  end
end

--- Refresh quickfix items in-place if the quickfix window is open with our title.
---@param tabpage integer
local function refresh_quickfix(tabpage)
  local qf_info = vim.fn.getqflist({ winid = 0, title = "" })
  if not qf_info.winid or qf_info.winid == 0 then
    return
  end
  if not (qf_info.title or ""):match("^CodeDiff pending comments") then
    return
  end

  local lifecycle = require("codediff.ui.lifecycle")
  local session = lifecycle.get_session(tabpage)
  local comments = store.list(tabpage)
  local items = build_quickfix_items(comments, session)
  local title = string.format("CodeDiff pending comments (%d)", #items)

  -- Preserve cursor position
  local cursor = vim.api.nvim_win_get_cursor(qf_info.winid)
  vim.fn.setqflist({}, "r", { title = title, items = items })
  -- Restore cursor (clamp to new list size)
  local new_count = #items
  if new_count > 0 then
    cursor[1] = math.min(cursor[1], new_count)
    pcall(vim.api.nvim_win_set_cursor, qf_info.winid, cursor)
  end
end

local function unsubscribe()
  if active_unsub then
    active_unsub()
    active_unsub = nil
  end
end

local M = {}

--- Check if the quickfix window is currently open with a CodeDiff comments title.
---@return integer? winid The quickfix window ID if open with our title, nil otherwise
local function find_open_comments_qf()
  local qf_info = vim.fn.getqflist({ winid = 0, title = "" })
  if qf_info.winid and qf_info.winid ~= 0 and (qf_info.title or ""):match("^CodeDiff pending comments") then
    return qf_info.winid
  end
  return nil
end

--- Close the comments quickfix if it is currently open.
---@return boolean closed True if a comments quickfix was found and closed
function M.close_if_open()
  local existing = find_open_comments_qf()
  if existing then
    vim.cmd("cclose")
    unsubscribe()
    return true
  end
  return false
end

--- Toggle the quickfix list for the given comments.
--- If already open, closes it. Otherwise builds and opens it.
---@param comments codediff.comments.Comment[]
---@param session table? The lifecycle session
---@return boolean opened True if quickfix was opened (false if closed)
function M.open(comments, session)
  -- Toggle: close if already showing our comments quickfix
  local existing = find_open_comments_qf()
  if existing then
    vim.cmd("cclose")
    unsubscribe()
    return false
  end

  local items = build_quickfix_items(comments, session)
  local title = string.format("CodeDiff pending comments (%d)", #items)
  vim.fn.setqflist({}, " ", { title = title, items = items })
  vim.cmd("copen")

  -- Set custom <CR> mapping on the quickfix buffer to navigate to
  -- the correct CodeDiff diff pane instead of opening a split.
  local qf_bufnr = vim.api.nvim_get_current_buf()
  vim.keymap.set("n", "<CR>", on_quickfix_select, {
    buffer = qf_bufnr,
    noremap = true,
    silent = true,
    nowait = true,
    desc = "Navigate to CodeDiff comment",
  })

  -- Bind the comment_list toggle key on the quickfix buffer so the user
  -- can press the same key to close the list from inside the quickfix window.
  local list_key = require("codediff.config").options.keymaps.view.comment_list
  if list_key then
    vim.keymap.set("n", list_key, function()
      M.close_if_open()
    end, {
      buffer = qf_bufnr,
      noremap = true,
      silent = true,
      nowait = true,
      desc = "Close CodeDiff comments list",
    })
  end

  -- Subscribe to store changes to keep quickfix in sync
  unsubscribe()
  active_unsub = store.subscribe(function(tabpage)
    vim.schedule(function()
      refresh_quickfix(tabpage)
    end)
  end)

  -- Clean up subscription when quickfix buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = qf_bufnr,
    once = true,
    callback = unsubscribe,
  })

  return true
end

--- Build quickfix items without opening. For testing or external use.
---@param comments codediff.comments.Comment[]
---@param session table?
---@return table[] items
function M.build_items(comments, session)
  return build_quickfix_items(comments, session)
end

return M
