--- Formats comments for submission and dispatches through configurable sinks.
---@module codediff.comments.drain

local model = require("codediff.comments.model")
local SIDE = model.SIDE
local split_lines = model.split_lines
local format_line_ref = model.format_line_ref
local sorted_comments = model.sorted_comments
local relative_path = model.relative_path

---@type codediff.Sink[]
local sinks = {}

---@param comments codediff.comments.Comment[]
---@param context codediff.SubmitContext
---@return string
local function format_submission(comments, context)
  local ordered = sorted_comments(comments)
  local lines = {
    string.format("CodeDiff review (%d comment%s)", #ordered, #ordered == 1 and "" or "s"),
  }
  for _, comment in ipairs(ordered) do
    local display_path = relative_path(comment.path, context.git_root)
    table.insert(lines, "")
    table.insert(lines, string.format("%s:%s (%s)", display_path, format_line_ref(comment), SIDE[comment.side].label))
    for _, line in ipairs(split_lines(comment.text)) do
      table.insert(lines, "  " .. line)
    end
  end
  return table.concat(lines, "\n")
end

--- Collect enabled sinks for a given context.
---@param context codediff.SubmitContext
---@return codediff.Sink[]
local function enabled_sinks(context)
  local result = {}
  for _, sink in ipairs(sinks) do
    if sink.enabled == nil or sink.enabled(context) then
      result[#result + 1] = sink
    end
  end
  return result
end

--- Default clipboard sink used when no sinks are registered.
---@type codediff.Sink
local clipboard_sink = {
  name = "clipboard",
  handler = function(comments, context, done)
    local payload = format_submission(comments, context)
    local ok_plus = pcall(vim.fn.setreg, "+", payload)
    local ok_unnamed = pcall(vim.fn.setreg, '"', payload)
    if not ok_plus and not ok_unnamed then
      done(false, "failed to write payload to clipboard registers")
    else
      done(true)
    end
  end,
}

local M = {}

--- Format comments into a submission payload string.
---@param comments codediff.comments.Comment[]
---@param context codediff.SubmitContext
---@return string
function M.format(comments, context)
  return format_submission(comments, context)
end

--- Register a named sink. Replaces any existing sink with the same name.
---@param sink codediff.Sink
function M.add_sink(sink)
  assert(type(sink.name) == "string" and sink.name ~= "", "sink requires a non-empty name")
  assert(type(sink.handler) == "function", "sink requires a handler function")
  M.remove_sink(sink.name)
  sinks[#sinks + 1] = sink
end

--- Remove a sink by name.
---@param name string
---@return boolean removed
function M.remove_sink(name)
  for i, s in ipairs(sinks) do
    if s.name == name then
      table.remove(sinks, i)
      return true
    end
  end
  return false
end

--- Return the list of registered sink names (for introspection/testing).
---@return string[]
function M.sink_names()
  return vim.iter(sinks):map(function(s)
    return s.name
  end):totable()
end

--- Submit comments through all enabled sinks.
--- Falls back to clipboard when no sinks are registered.
---
--- Returns:
---   should_clear: true if comments should be cleared (at least one
---                 clear_on_success sink succeeded, and none failed)
---   results:      per-sink result list for notification
---@param comments codediff.comments.Comment[]
---@param context codediff.SubmitContext
---@param on_complete fun(should_clear: boolean, results: {name: string, ok: boolean, err?: string}[])
function M.submit(comments, context, on_complete)
  local targets = enabled_sinks(context)

  -- Fallback: no sinks registered → use clipboard
  if #sinks == 0 and #targets == 0 then
    targets = { clipboard_sink }
  end

  if #targets == 0 then
    on_complete(false, {})
    return
  end

  local results = {}
  local pending = #targets

  for _, sink in ipairs(targets) do
    local sink_name = sink.name
    local clear = sink.clear_on_success ~= false -- default true
    local ok_call, call_err = pcall(sink.handler, comments, context, function(ok, err)
      results[#results + 1] = { name = sink_name, ok = ok, err = err, clear = clear }
      pending = pending - 1
      if pending == 0 then
        local should_clear = false
        local any_failed = false
        for _, r in ipairs(results) do
          if r.ok and r.clear then
            should_clear = true
          end
          if not r.ok then
            any_failed = true
          end
        end
        -- Don't clear if any sink that wants clear actually failed
        if any_failed then
          for _, r in ipairs(results) do
            if not r.ok and r.clear then
              should_clear = false
            end
          end
        end
        on_complete(should_clear, results)
      end
    end)
    if not ok_call then
      results[#results + 1] = { name = sink_name, ok = false, err = tostring(call_err), clear = clear }
      pending = pending - 1
      if pending == 0 then
        on_complete(false, results)
      end
    end
  end
end

--- Reset module state. For tests.
function M._reset_for_tests()
  sinks = {}
end

return M
