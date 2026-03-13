-- Pure in-memory event-sourced comment store, keyed by tabpage.
local M = {}

local model = require("codediff.comments.model")
local EVENT = model.EVENT

---@class codediff.comments.TabStream
---@field next_id integer
---@field events codediff.comments.Event[]
---@field snapshot codediff.comments.Comment[]

---@type table<integer, codediff.comments.TabStream>
local tabs = {}

---@type fun(tabpage: integer, event_type: string?)[]
local listeners = {}

local suppress_notify = false

---@param tabpage integer
---@param event_type string?
local function notify_listeners(tabpage, event_type)
  if suppress_notify then
    return
  end
  for _, cb in ipairs(listeners) do
    cb(tabpage, event_type)
  end
end

---@param tabpage integer
---@return codediff.comments.TabStream
local function ensure(tabpage)
  if not tabs[tabpage] then
    tabs[tabpage] = { next_id = 1, events = {}, snapshot = {} }
  end
  return tabs[tabpage]
end

---@param comment codediff.comments.Comment
---@param changes codediff.comments.CommentPatch
---@return codediff.comments.Comment
local function apply_patch(comment, changes)
  local patched = vim.deepcopy(comment)
  for k, v in pairs(changes) do
    if (k == "end_line" or k == "content_lines") and v == false then
      patched[k] = nil
    else
      patched[k] = v
    end
  end
  return patched
end

---@param events codediff.comments.Event[]
---@return codediff.comments.Comment[]
local function project(events)
  local result = {}
  for _, ev in ipairs(events) do
    if ev.type == EVENT.ADDED then
      result[#result + 1] = vim.deepcopy(ev.comment)
    elseif ev.type == EVENT.UPDATED then
      for i, c in ipairs(result) do
        if c.id == ev.id then
          result[i] = apply_patch(c, ev.changes)
          break
        end
      end
    elseif ev.type == EVENT.DELETED then
      for i, c in ipairs(result) do
        if c.id == ev.id then
          table.remove(result, i)
          break
        end
      end
    end
  end
  return result
end

---@param snapshot codediff.comments.Comment[]
---@param comment_id integer
---@return codediff.comments.Comment?
local function find(snapshot, comment_id)
  return vim.iter(snapshot):find(function(c)
    return c.id == comment_id
  end)
end

---@param tabpage integer
---@param draft { side: "left"|"right", path: string, line: integer, end_line?: integer, text: string }
---@return integer id
function M.add(tabpage, draft)
  local stream = ensure(tabpage)
  local id = stream.next_id
  stream.next_id = id + 1
  ---@type codediff.comments.Comment
  local comment = {
    id = id,
    side = draft.side,
    path = draft.path,
    line = draft.line,
    end_line = draft.end_line,
    text = draft.text,
    content_lines = draft.content_lines,
  }
  stream.events[#stream.events + 1] = { type = EVENT.ADDED, comment = comment }
  stream.snapshot = project(stream.events)
  notify_listeners(tabpage, EVENT.ADDED)
  return id
end

---@param tabpage integer
---@param comment_id integer
---@param changes codediff.comments.CommentPatch
---@param reason? string
---@return boolean ok
function M.update(tabpage, comment_id, changes, reason)
  local stream = ensure(tabpage)
  if not find(stream.snapshot, comment_id) then
    return false
  end
  stream.events[#stream.events + 1] = {
    type = EVENT.UPDATED,
    id = comment_id,
    changes = vim.deepcopy(changes),
    reason = reason,
  }
  stream.snapshot = project(stream.events)
  notify_listeners(tabpage, EVENT.UPDATED)
  return true
end

---@param tabpage integer
---@param comment_id integer
---@param reason? string
---@return boolean ok
function M.delete(tabpage, comment_id, reason)
  local stream = ensure(tabpage)
  if not find(stream.snapshot, comment_id) then
    return false
  end
  stream.events[#stream.events + 1] = {
    type = EVENT.DELETED,
    id = comment_id,
    reason = reason,
  }
  stream.snapshot = project(stream.events)
  notify_listeners(tabpage, EVENT.DELETED)
  return true
end

---@param tabpage integer
---@param comment_id integer
---@return codediff.comments.Comment?
function M.get(tabpage, comment_id)
  local stream = tabs[tabpage]
  if not stream then
    return nil
  end
  local c = find(stream.snapshot, comment_id)
  if c then
    return vim.deepcopy(c)
  end
  return nil
end

---@param tabpage integer
---@return codediff.comments.Comment[]
function M.list(tabpage)
  local stream = tabs[tabpage]
  if not stream then
    return {}
  end
  return stream.snapshot
end

---@param tabpage integer
---@return integer
function M.count(tabpage)
  local stream = tabs[tabpage]
  if not stream then
    return 0
  end
  return #stream.snapshot
end

---@param tabpage integer
---@return boolean
function M.has_comments(tabpage)
  return M.count(tabpage) > 0
end

---@param tabpage integer
function M.clear(tabpage)
  tabs[tabpage] = nil
  notify_listeners(tabpage, nil)
end

--- Subscribe to store changes. Returns an unsubscribe function.
---@param callback fun(tabpage: integer, event_type: string?)
---@return fun() unsubscribe
function M.subscribe(callback)
  listeners[#listeners + 1] = callback
  return function()
    for i, cb in ipairs(listeners) do
      if cb == callback then
        table.remove(listeners, i)
        return
      end
    end
  end
end

---@param tabpage integer
---@param fn fun()
function M.batch(tabpage, fn)
  suppress_notify = true
  fn()
  suppress_notify = false
  notify_listeners(tabpage, nil)
end

function M._reset_for_tests()
  tabs = {}
  listeners = {}
  suppress_notify = false
end

return M
