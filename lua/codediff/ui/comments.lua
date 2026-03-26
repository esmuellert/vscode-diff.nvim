-- Public API facade for CodeDiff pending comments.
-- Orchestrates store, drain, render, editor, and quickfix modules.
local M = {}

local lifecycle = require("codediff.ui.lifecycle")
local model = require("codediff.comments.model")
local store = require("codediff.comments.store")
local drain = require("codediff.comments.drain")
local render = require("codediff.ui.comments.render")
local editor = require("codediff.ui.comments.editor")
local quickfix = require("codediff.ui.comments.quickfix")
local snapshot_cache = require("codediff.comments.snapshot_cache")

local SIDE = model.SIDE

---@return integer? tabpage
---@return table? session
local function get_session_for_current_context()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local session = lifecycle.get_session(current_tab)
  if session then
    return current_tab, session
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local tabpage = lifecycle.find_tabpage_by_buffer(bufnr)
  if not tabpage then
    return nil, nil
  end

  return tabpage, lifecycle.get_session(tabpage)
end

---@param session table?
---@return boolean
local function is_comment_session(session)
  if not session then
    return false
  end

  if not session.original_bufnr or not session.modified_bufnr or not vim.api.nvim_buf_is_valid(session.original_bufnr) or not vim.api.nvim_buf_is_valid(session.modified_bufnr) then
    return false
  end

  if (session.mode == "explorer" or session.mode == "history") and session.original_path == "" and session.modified_path == "" then
    return false
  end

  return true
end

---@param session table
---@param bufnr integer
---@return boolean
local function is_diff_buffer(session, bufnr)
  return bufnr == session.original_bufnr or bufnr == session.modified_bufnr
end

---@param session table
---@param bufnr integer
---@return "left"|"right"|nil
local function side_for_buffer(session, bufnr)
  if bufnr == session.original_bufnr then
    return "left"
  end
  if bufnr == session.modified_bufnr then
    return "right"
  end
  return nil
end

---@param session table
---@param bufnr integer
---@return string
local function buffer_path_for_comment(session, bufnr)
  local side = side_for_buffer(session, bufnr)
  if side then
    local path = session[SIDE[side].path_key]
    if path and path ~= "" then
      return path
    end
    return SIDE[side].fallback
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name ~= "" and name or "(unknown pane)"
end

--- Capture buffer lines covered by a comment range.
---@param bufnr integer
---@param line integer
---@param end_line? integer
---@return string[]
local function capture_content_lines(bufnr, line, end_line)
  local last = end_line or line
  local count = vim.api.nvim_buf_line_count(bufnr)
  if line > count then
    return {}
  end
  last = math.min(last, count)
  return vim.api.nvim_buf_get_lines(bufnr, line - 1, last, false)
end

---@return { tabpage: integer, session: table, bufnr: integer }?
local function require_comment_session()
  local tabpage, session = get_session_for_current_context()
  if not tabpage or not is_comment_session(session) then
    vim.notify("Pending comments are only available in active CodeDiff diff panes", vim.log.levels.WARN)
    return nil
  end
  return { tabpage = tabpage, session = session, bufnr = vim.api.nvim_get_current_buf() }
end

---@param tabpage integer
---@param session table
---@param notify_on_drop? boolean
local function sync_visible_positions(tabpage, session, notify_on_drop)
  local comments = store.list(tabpage)
  if #comments == 0 then
    return
  end

  local sync = render.capture_position_patches(tabpage, session, comments)

  if #sync.updates > 0 or #sync.stale_ids > 0 then
    store.batch(tabpage, function()
      for _, patch in ipairs(sync.updates) do
        store.update(tabpage, patch.id, patch.changes, "position_sync")
      end

      for _, id in ipairs(sync.stale_ids) do
        store.delete(tabpage, id, "stale")
      end
    end)
  end

  if notify_on_drop and #sync.stale_ids > 0 then
    vim.notify(string.format("Dropped %d stale pending comment(s)", #sync.stale_ids), vim.log.levels.WARN)
  end
end

---@param tabpage integer
---@param session table
---@return codediff.SubmitContext
local function make_submit_context(tabpage, session)
  return {
    tabpage = tabpage,
    submitted_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    mode = session.mode,
    git_root = session.git_root,
    original_revision = session.original_revision,
    modified_revision = session.modified_revision,
    original_path = session.original_path,
    modified_path = session.modified_path,
  }
end

---@param bufnr integer
---@return integer start_line
---@return integer? end_line
local function read_visual_marks(bufnr)
  local ok_start, mark_start = pcall(vim.api.nvim_buf_get_mark, bufnr, "<")
  local ok_end, mark_end = pcall(vim.api.nvim_buf_get_mark, bufnr, ">")
  if ok_start and ok_end and mark_start[1] > 0 and mark_end[1] > 0 and mark_end[1] > mark_start[1] then
    return mark_start[1], mark_end[1]
  end
  return vim.api.nvim_win_get_cursor(0)[1], nil
end

---@param comment_id integer?
---@return codediff.comments.Comment? comment
---@return integer? tabpage
local function get_target_comment(comment_id)
  local ctx = require_comment_session()
  if not ctx then
    return nil, nil
  end

  sync_visible_positions(ctx.tabpage, ctx.session, true)

  local comments = store.list(ctx.tabpage)
  if #comments == 0 then
    return nil, nil
  end

  if comment_id then
    for _, comment in ipairs(comments) do
      if comment.id == comment_id then
        return comment, ctx.tabpage
      end
    end
    vim.notify(string.format("No pending comment found with id %d", comment_id), vim.log.levels.WARN)
    return nil, nil
  end

  local bufnr = ctx.bufnr
  if not is_diff_buffer(ctx.session, bufnr) then
    vim.notify("Move cursor to a CodeDiff diff pane before operating on comments", vim.log.levels.WARN)
    return nil, nil
  end

  local side = side_for_buffer(ctx.session, bufnr)
  local side_meta = side and SIDE[side]
  local path = side_meta and ctx.session[side_meta.path_key] or nil
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for i = #comments, 1, -1 do
    local comment = comments[i]
    if comment.side == side and comment.path == path then
      local start_line = comment.line
      local stop_line = comment.end_line or start_line
      if line >= start_line and line <= stop_line then
        return comment, ctx.tabpage
      end
    end
  end

  return nil, nil
end

---@param tabpage integer
---@return integer count
function M.clear_session_comments(tabpage)
  local count = store.count(tabpage)
  render.clear_tab(tabpage)
  store.clear(tabpage)
  return count
end

--- Snapshot current comments for a tabpage to disk so they survive toggle/restart.
---@param tabpage integer
local function snapshot_session_comments(tabpage)
  if not store.has_comments(tabpage) then
    return
  end
  local sess = lifecycle.get_session(tabpage)
  if not sess then
    return
  end
  local sid = snapshot_cache.session_id_from_session(sess)
  snapshot_cache.save(sid, store.list(tabpage))
end

--- Remove any persisted snapshot for a tabpage's session.
---@param tabpage integer
local function remove_snapshot(tabpage)
  local sess = lifecycle.get_session(tabpage)
  if not sess then
    return
  end
  local sid = snapshot_cache.session_id_from_session(sess)
  snapshot_cache.remove(sid)
end

---@param tabpage integer
---@param session table
---@return integer count Number of comments restored
local function restore_session_comments(tabpage, session)
  if store.has_comments(tabpage) then
    return 0
  end
  local sid = snapshot_cache.session_id_from_session(session)
  local saved = snapshot_cache.restore(sid)
  -- Consume the snapshot so it can't re-trigger (e.g., after user deletes all comments)
  snapshot_cache.remove(sid)
  if not saved or #saved == 0 then
    return 0
  end

  local dropped = 0
  for _, comment in ipairs(saved) do
    local side_meta = SIDE[comment.side]
    local buf = side_meta and session[side_meta.bufnr_key]
    local anchored = comment.content_lines

    -- Drop if content at stored position no longer matches
    if anchored and #anchored > 0 and buf and vim.api.nvim_buf_is_valid(buf) and comment.path == (side_meta and session[side_meta.path_key]) then
      local current = capture_content_lines(buf, comment.line, comment.end_line)
      if table.concat(current, "\n") ~= table.concat(anchored, "\n") then
        dropped = dropped + 1
        goto continue
      end
    end

    store.add(tabpage, {
      side = comment.side,
      path = comment.path,
      line = comment.line,
      end_line = comment.end_line,
      text = comment.text,
      content_lines = anchored,
    })

    ::continue::
  end

  if dropped > 0 then
    vim.notify(string.format("Dropped %d stale comment(s) — content no longer found", dropped), vim.log.levels.WARN)
  end

  local restored = store.list(tabpage)
  if #restored > 0 then
    render.reconcile(tabpage, session, restored)
  end
  return #restored
end

---@param tabpage integer
---@return codediff.comments.Comment[]
function M.get_comments(tabpage)
  local session = lifecycle.get_session(tabpage)
  if session then
    sync_visible_positions(tabpage, session, false)
  end
  return store.list(tabpage)
end

---@return boolean
function M.list_comments()
  local ctx = require_comment_session()
  if not ctx then
    return false
  end

  sync_visible_positions(ctx.tabpage, ctx.session, true)

  local comments = store.list(ctx.tabpage)
  quickfix.open(comments, ctx.session)
  return true
end

---@param comment_id integer?
---@return boolean
function M.remove_comment(comment_id)
  local comment, tabpage = get_target_comment(comment_id)
  if not comment or not tabpage then
    return false
  end

  render.clear_tab(tabpage)
  store.delete(tabpage, comment.id)

  local session = lifecycle.get_session(tabpage)
  if session then
    render.reconcile(tabpage, session, store.list(tabpage))
  end

  return true
end

---@param text string?
---@param range_line1 integer?
---@param range_line2 integer?
---@return boolean
function M.add_comment(text, range_line1, range_line2)
  local tabpage, session = get_session_for_current_context()
  if not tabpage or not is_comment_session(session) then
    vim.notify("Pending comments are only available in active CodeDiff diff panes", vim.log.levels.WARN)
    return false
  end

  local bufnr = vim.api.nvim_get_current_buf()
  if not is_diff_buffer(session, bufnr) then
    vim.notify("Move cursor to a CodeDiff diff pane before adding a comment", vim.log.levels.WARN)
    return false
  end

  local message = vim.trim(text or "")
  if message == "" then
    return false
  end

  local line = range_line1 or vim.api.nvim_win_get_cursor(0)[1]
  local end_line = nil
  if range_line1 and range_line2 and range_line2 > range_line1 then
    end_line = range_line2
  end

  store.add(tabpage, {
    side = side_for_buffer(session, bufnr),
    path = buffer_path_for_comment(session, bufnr),
    line = line,
    end_line = end_line,
    text = message,
    content_lines = capture_content_lines(bufnr, line, end_line),
  })

  render.reconcile(tabpage, session, store.list(tabpage))
  return true
end

---@param opts? { visual?: boolean, range_line1?: integer, range_line2?: integer }
---@return boolean
function M.open_add_editor(opts)
  opts = opts or {}
  local ctx = require_comment_session()
  if not ctx then
    return false
  end

  local bufnr = ctx.bufnr
  local line, end_line
  if opts.range_line1 and opts.range_line2 and opts.range_line2 > opts.range_line1 then
    line = opts.range_line1
    end_line = opts.range_line2
  elseif opts.visual then
    line, end_line = read_visual_marks(bufnr)
  else
    line = vim.api.nvim_win_get_cursor(0)[1]
  end

  if not is_diff_buffer(ctx.session, bufnr) then
    vim.notify("Move cursor to a CodeDiff diff pane before adding a comment", vim.log.levels.WARN)
    return false
  end

  -- Capture side, path, and content eagerly before creating the editor.
  -- ctx.session is mutable and its bufnr fields may change by the time
  -- on_submit fires (e.g., user switches files in explorer).
  local side = side_for_buffer(ctx.session, bufnr)
  local path = buffer_path_for_comment(ctx.session, bufnr)
  local content_lines = capture_content_lines(bufnr, line, end_line)

  local title = end_line and string.format("Add Comment (L%d-%d)", line, end_line) or "Add Comment"
  return editor.open({
    title = title,
    initial_text = "",
    on_submit = function(text)
      local message = vim.trim(text)
      if message == "" then
        return false
      end
      store.add(ctx.tabpage, {
        side = side,
        path = path,
        line = line,
        end_line = end_line,
        text = message,
        content_lines = content_lines,
      })
      render.reconcile(ctx.tabpage, ctx.session, store.list(ctx.tabpage))
      return true
    end,
  })
end

---@param comment_id integer?
---@param new_text string?
---@return boolean
function M.edit_comment(comment_id, new_text)
  local comment, tabpage = get_target_comment(comment_id)
  if not comment or not tabpage then
    return false
  end

  local message = vim.trim(new_text or "")
  if message == "" then
    vim.notify("Comment text cannot be empty", vim.log.levels.WARN)
    return false
  end

  if comment.text == message then
    return true
  end

  store.update(tabpage, comment.id, { text = message })

  local session = lifecycle.get_session(tabpage)
  if session then
    render.reconcile(tabpage, session, store.list(tabpage))
  end

  return true
end

---@param comment_id integer?
---@return boolean
function M.open_edit_editor(comment_id)
  local comment, tabpage = get_target_comment(comment_id)
  if not comment or not tabpage then
    return false
  end

  return editor.open({
    title = string.format("Edit Comment c%d", comment.id),
    initial_text = comment.text,
    cursor_to_end = true,
    on_submit = function(text)
      return M.edit_comment(comment.id, text)
    end,
  })
end

---@return boolean
function M.clear_comments()
  local ctx = require_comment_session()
  if not ctx then
    return false
  end

  remove_snapshot(ctx.tabpage)
  M.clear_session_comments(ctx.tabpage)
  editor.close_active()
  return true
end

---@return boolean
function M.submit_comments()
  local ctx = require_comment_session()
  if not ctx then
    return false
  end

  sync_visible_positions(ctx.tabpage, ctx.session, true)

  local comments = store.list(ctx.tabpage)
  if #comments == 0 then
    return false
  end

  local context = make_submit_context(ctx.tabpage, ctx.session)
  local submitted = false

  drain.submit(comments, context, function(should_clear, results)
    for _, r in ipairs(results) do
      if not r.ok then
        vim.notify(
          string.format("Sink '%s' failed: %s", r.name, r.err or "unknown error"),
          vim.log.levels.ERROR
        )
      end
    end

    if should_clear then
      remove_snapshot(ctx.tabpage)
      M.clear_session_comments(ctx.tabpage)
      editor.close_active()
      submitted = true
    elseif #results == 0 then
      vim.notify("No enabled sinks to submit comments to", vim.log.levels.WARN)
    end
  end)

  return submitted
end

function M.setup()
  if M._setup_done then
    return
  end
  M._setup_done = true

  render.setup()

  local group = vim.api.nvim_create_augroup("CodeDiffComments", { clear = true })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffClose",
    callback = function(args)
      editor.close_active()
      if args and args.data and args.data.tabpage then
        snapshot_session_comments(args.data.tabpage)
        M.clear_session_comments(args.data.tabpage)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "WinScrolled", "BufWinEnter", "TabEnter" }, {
    group = group,
    callback = function()
      local tabpage = vim.api.nvim_get_current_tabpage()
      local session = lifecycle.get_session(tabpage)
      if not session then
        return
      end
      -- Attempt snapshot restore if store is empty
      if not store.has_comments(tabpage) then
        restore_session_comments(tabpage, session)
      end
      if store.has_comments(tabpage) then
        render.reconcile(tabpage, session, store.list(tabpage))
      end
    end,
  })

  -- Non-sticky comment visibility: show/hide popups based on viewport.
  local viewport_timer = (vim.uv or vim.loop).new_timer()
  vim.api.nvim_create_autocmd({ "WinScrolled", "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function()
      if model.is_sticky() then
        return
      end
      viewport_timer:stop()
      viewport_timer:start(30, 0, vim.schedule_wrap(function()
        local tabpage = vim.api.nvim_get_current_tabpage()
        local session = lifecycle.get_session(tabpage)
        if not session or not store.has_comments(tabpage) then
          return
        end
        render.update_viewport_popups(tabpage, session, store.list(tabpage))
      end))
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        local session = lifecycle.get_session(tabpage)
        if session and store.has_comments(tabpage) then
          render.reconcile(tabpage, session, store.list(tabpage))
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      render.refresh_highlights()
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        snapshot_session_comments(tabpage)
      end
    end,
  })
end

function M._reset_for_tests()
  editor.close_active()
  render._reset_for_tests()
  store._reset_for_tests()
  drain._reset_for_tests()
  snapshot_cache._reset_for_tests()
end

--- Register a named submission sink.
---@param sink codediff.Sink
function M.add_sink(sink)
  drain.add_sink(sink)
end

--- Remove a sink by name.
---@param name string
---@return boolean removed
function M.remove_sink(name)
  return drain.remove_sink(name)
end

--- Format comments into a submission payload string (utility for sinks).
---@param comments codediff.comments.Comment[]
---@param context codediff.SubmitContext
---@return string
function M.format(comments, context)
  return drain.format(comments, context)
end

return M
