-- Shared types, constants, and helpers for the comments subsystem.
local M = {}

---@class codediff.comments.Comment
---@field id integer Unique comment identifier within the tab session
---@field side "left"|"right" Which diff pane the comment belongs to
---@field path string File path the comment is associated with
---@field line integer 1-indexed start line number
---@field end_line? integer 1-indexed end line number (nil means single-line comment)
---@field text string Comment body text
---@field content_lines? string[] Buffer lines the comment was anchored to (for validation on restore)

---@class codediff.comments.CommentPatch
---@field text? string
---@field line? integer
---@field end_line? integer|false false = clear end_line
---@field path? string
---@field side? "left"|"right"
---@field content_lines? string[]|false false = clear content_lines

---@alias codediff.comments.Event
---| { type: "comment_added", comment: codediff.comments.Comment }
---| { type: "comment_updated", id: integer, changes: codediff.comments.CommentPatch, reason?: string }
---| { type: "comment_deleted", id: integer, reason?: string }

---@class codediff.SubmitContext
---@field tabpage integer Tab page ID of the diff session
---@field submitted_at string ISO 8601 timestamp (UTC)
---@field mode string Session mode ("explorer", "standalone", "history")
---@field git_root? string Git root directory
---@field original_revision? string Original revision
---@field modified_revision? string Modified revision
---@field original_path? string Original file path
---@field modified_path? string Modified file path

--- Callback a sink invokes when it finishes (sync or async).
---@alias codediff.SinkDone fun(ok: boolean, err?: string)

--- The function a sink uses to process submitted comments.
---@alias codediff.SinkHandler fun(comments: codediff.comments.Comment[], context: codediff.SubmitContext, done: codediff.SinkDone)

--- A named submission sink.
---@class codediff.Sink
---@field name string Unique sink identifier (e.g. "agent", "github", "clipboard")
---@field handler codediff.SinkHandler
---@field enabled? fun(context: codediff.SubmitContext): boolean Dynamic gate; omit to always enable
---@field clear_on_success? boolean Whether successful delivery should contribute to clearing comments (default: true)

---@class codediff.CommentUIOptions
---@field width integer Floating editor width (columns)
---@field height integer Floating editor height (lines)
---@field opacity integer Window blend (0 = opaque, 100 = fully transparent)
---@field submit_keys string[] Keys to submit from editor
---@field cancel_keys string[] Keys to cancel editor
---@field editor_mode "insert"|"normal" Initial editor mode

M.EVENT = {
  ADDED = "comment_added",
  UPDATED = "comment_updated",
  DELETED = "comment_deleted",
}

M.SIDE = {
  left = { bufnr_key = "original_bufnr", path_key = "original_path", sort = 0, label = "old", fallback = "(left pane)" },
  right = { bufnr_key = "modified_bufnr", path_key = "modified_path", sort = 1, label = "new", fallback = "(right pane)" },
}

---@param text string?
---@return string[]
function M.split_lines(text)
  local lines = vim.split(text or "", "\n", { plain = true })
  if #lines == 0 then
    return { "" }
  end
  return lines
end

---@param text string
---@param max_width integer
---@return string
function M.truncate_text(text, max_width)
  if #text <= max_width then
    return text
  end
  if max_width <= 3 then
    return text:sub(1, max_width)
  end
  return text:sub(1, max_width - 3) .. "..."
end

---@param comment codediff.comments.Comment
---@return string
function M.format_line_ref(comment)
  if comment.end_line and comment.end_line > comment.line then
    return string.format("%d-%d", comment.line, comment.end_line)
  end
  return tostring(comment.line)
end

---@param comments codediff.comments.Comment[]
---@return codediff.comments.Comment[]
function M.sorted_comments(comments)
  local ordered = vim.deepcopy(comments)
  table.sort(ordered, function(a, b)
    local ap = tostring(a.path or "")
    local bp = tostring(b.path or "")
    if ap == bp then
      local al = a.line
      local bl = b.line
      if al == bl then
        local as = (M.SIDE[a.side] or {}).sort or 99
        local bs = (M.SIDE[b.side] or {}).sort or 99
        if as == bs then
          return a.id < b.id
        end
        return as < bs
      end
      return al < bl
    end
    return ap < bp
  end)
  return ordered
end

---@param value any
---@param default string[]
---@return string[]
function M.normalize_key_list(value, default)
  if type(value) == "string" and value ~= "" then
    value = { value }
  end
  if type(value) ~= "table" or #value == 0 then
    return default
  end
  local seen = {}
  local out = vim
    .iter(value)
    :filter(function(key)
      if type(key) ~= "string" or key == "" or seen[key] then
        return false
      end
      seen[key] = true
      return true
    end)
    :totable()
  return #out > 0 and out or default
end

---@return codediff.CommentUIOptions
function M.get_ui_options()
  local config = require("codediff.config")
  local comment_opts = config.options.comments or {}
  local ui_opts = comment_opts.ui or {}

  local opacity = ui_opts.opacity
  if type(opacity) ~= "number" then
    opacity = 0
  end
  opacity = math.max(0, math.min(100, opacity))

  local editor_mode = ui_opts.editor_mode
  if type(editor_mode) ~= "string" then
    editor_mode = "insert"
  else
    editor_mode = editor_mode:lower()
  end
  if editor_mode ~= "normal" then
    editor_mode = "insert"
  end

  return {
    width = ui_opts.width or 72,
    height = ui_opts.height or 6,
    opacity = opacity,
    submit_keys = M.normalize_key_list(ui_opts.submit_keys, { "<CR>" }),
    cancel_keys = M.normalize_key_list(ui_opts.cancel_keys, { "q" }),
    editor_mode = editor_mode,
  }
end

---@param path string
---@param git_root string?
---@return string
function M.relative_path(path, git_root)
  if not git_root or git_root == "" then
    return path
  end
  local prefix = git_root .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return path
end

---@return boolean
function M.is_sticky()
  local config = require("codediff.config")
  return config.options.comments == nil or config.options.comments.sticky ~= false
end

return M
