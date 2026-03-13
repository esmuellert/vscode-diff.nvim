--- Formats comments for submission and dispatches through configurable sinks.
---@module codediff.comments.drain

local model = require("codediff.comments.model")
local SIDE = model.SIDE
local split_lines = model.split_lines
local format_line_ref = model.format_line_ref
local sorted_comments = model.sorted_comments
local relative_path = model.relative_path

---@type codediff.SubmitHook?
local submit_hook = nil

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

---@param hook codediff.SubmitHook
---@param payload string
---@param comments codediff.comments.Comment[]
---@param context codediff.SubmitContext
---@return boolean ok
---@return string? error
local function run_submit_hook(hook, payload, comments, context)
  local ok_call, result_or_err, hook_err = pcall(hook, payload, comments, context)
  if not ok_call then
    return false, tostring(result_or_err)
  end
  if result_or_err == false then
    return false, hook_err or "submit hook returned false"
  end
  return true, nil
end

---@param payload string
---@return boolean ok
---@return string? transport_or_error
local function submit_to_clipboard(payload)
  local ok_plus = pcall(vim.fn.setreg, "+", payload)
  local ok_unnamed = pcall(vim.fn.setreg, '"', payload)
  if not ok_plus and not ok_unnamed then
    return false, "failed to write payload to clipboard registers"
  end
  return true, "clipboard"
end

---@param payload string
---@param comments codediff.comments.Comment[]
---@param context codediff.SubmitContext
---@return boolean ok
---@return string? transport_or_error
local function submit_to_transport(payload, comments, context)
  if submit_hook then
    local ok_hook, hook_err = run_submit_hook(submit_hook, payload, comments, context)
    if not ok_hook then
      return false, hook_err
    end
    return true, "hook"
  end
  if type(vim.g.codediff_comment_submit_hook) == "function" then
    local ok_hook, hook_err = run_submit_hook(vim.g.codediff_comment_submit_hook, payload, comments, context)
    if not ok_hook then
      return false, hook_err
    end
    return true, "hook"
  end
  return submit_to_clipboard(payload)
end

local M = {}

--- Format comments into a submission payload string.
---@param comments codediff.comments.Comment[]
---@param context codediff.SubmitContext
---@return string
function M.format(comments, context)
  return format_submission(comments, context)
end

--- Submit comments through the sink chain: hook -> vim.g hook -> clipboard.
--- Does NOT clear the store. Returns ok, transport_name_or_error.
---@param comments codediff.comments.Comment[]
---@param context codediff.SubmitContext
---@return boolean ok
---@return string? transport_or_error
function M.submit(comments, context)
  local payload = format_submission(comments, context)
  return submit_to_transport(payload, comments, context)
end

--- Set or clear the module-level submit hook.
---@param hook codediff.SubmitHook?
function M.set_submit_hook(hook)
  submit_hook = hook
end

--- Reset module state. For tests.
function M._reset_for_tests()
  submit_hook = nil
end

return M
