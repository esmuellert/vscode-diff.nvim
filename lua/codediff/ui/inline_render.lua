-- Inline diff rendering orchestrator
-- Manages per-buffer state, async git pipeline, and global mode autocmds.
-- Completely independent from :CodeDiff sessions (uses separate state).
local M = {}

local DEFAULT_BASE = ":0" -- git index, matches `git diff` default

-- Per-buffer state: keyed by bufnr
local inline_state = {}

-- Global mode state
local global_state = {
  enabled = false,
  base = nil, -- nil = use DEFAULT_BASE
  augroup = nil,
}

-- Guard for lazy highlight initialization
local highlights_initialized = false

local function ensure_highlights()
  if not highlights_initialized then
    local highlights = require("codediff.ui.highlights")
    highlights.setup()
    highlights_initialized = true
  end
end

-- Check if a buffer is part of an active :CodeDiff session.
-- The codediff-inline namespace is shared, so rendering on a buffer
-- that already has a :CodeDiff inline view would cause conflicts.
local function is_in_codediff_session(bufnr)
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return false
  end
  -- find_tabpage_by_buffer returns tabpage if buffer is in an active session
  return lifecycle.find_tabpage_by_buffer(bufnr) ~= nil
end

-- Internal: fetch git content, compute diff, and render
function M.render_buf(bufnr, base)
  base = base or global_state.base or DEFAULT_BASE

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then
    return
  end

  if is_in_codediff_session(bufnr) then
    return
  end

  local git = require("codediff.core.git")
  git.get_buf_file_content(file_path, base, function(err, original_lines)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      if err then
        -- Non-git buffer or git error: silent no-op
        if err:match("Not in a git repository") then
          return
        end
        -- File not in base revision (new file): treat as all-added
        if err:match("not found in revision") then
          original_lines = {}
        else
          vim.notify("[codediff] " .. err, vim.log.levels.WARN)
          return
        end
      end

      ensure_highlights()

      local modified_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local config = require("codediff.config")
      local diff_result = require("codediff.core.diff").compute_diff(original_lines, modified_lines, {
        max_computation_time_ms = config.options.diff.max_computation_time_ms,
        ignore_trim_whitespace = config.options.diff.ignore_trim_whitespace,
      })

      require("codediff.ui.inline").render_inline_diff(bufnr, diff_result, original_lines, modified_lines)

      inline_state[bufnr] = { active = true, base = base }
    end)
  end)
end

-- Clear inline diff decorations and remove state for a buffer
function M.clear_buf(bufnr)
  local inline = require("codediff.ui.inline")
  inline.clear(bufnr)
  inline_state[bufnr] = nil
end

-- Toggle inline diff rendering
-- @param show boolean|nil: true = show, false = hide, nil = toggle
-- @param global boolean|nil: if true, applies to all git-tracked buffers
function M.toggle(show, global)
  if global then
    -- Resolve toggle
    if show == nil then
      show = not global_state.enabled
    end
    if show then
      M.enable_global()
    else
      M.disable_global()
    end
  else
    local bufnr = vim.api.nvim_get_current_buf()
    -- Resolve toggle
    if show == nil then
      show = not (inline_state[bufnr] and inline_state[bufnr].active)
    end
    if show then
      M.render_buf(bufnr)
    else
      M.clear_buf(bufnr)
    end
  end
end

-- Change base revision for inline diff
-- @param base string|nil: revision (e.g. "HEAD", "HEAD~1", "main"), nil = reset to index
-- @param global boolean|nil: if true, applies to all buffers
function M.change_base(base, global)
  base = base or DEFAULT_BASE

  if global then
    global_state.base = base
    for buf, state in pairs(inline_state) do
      if state.active and vim.api.nvim_buf_is_valid(buf) then
        M.render_buf(buf, base)
      end
    end
  else
    local bufnr = vim.api.nvim_get_current_buf()
    if inline_state[bufnr] and inline_state[bufnr].active then
      M.render_buf(bufnr, base)
    end
  end
end

-- Enable global mode: render inline diffs on all file buffers, auto-render on BufEnter
function M.enable_global()
  if global_state.enabled then
    return
  end
  global_state.enabled = true

  local augroup = vim.api.nvim_create_augroup("codediff_inline_global", { clear = true })
  global_state.augroup = augroup

  -- Render current buffer immediately
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype == "" then
    M.render_buf(bufnr)
  end

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(args)
      if vim.bo[args.buf].buftype == "" and not (inline_state[args.buf] and inline_state[args.buf].active) then
        M.render_buf(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    callback = function(args)
      if inline_state[args.buf] and inline_state[args.buf].active then
        M.render_buf(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup,
    callback = function(args)
      inline_state[args.buf] = nil
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = function()
      highlights_initialized = false
      for buf, state in pairs(inline_state) do
        if state.active and vim.api.nvim_buf_is_valid(buf) then
          M.render_buf(buf)
        end
      end
    end,
  })
end

-- Disable global mode: clear all inline diffs and remove autocmds
function M.disable_global()
  if not global_state.enabled then
    return
  end

  local inline = require("codediff.ui.inline")
  for buf, _ in pairs(inline_state) do
    if vim.api.nvim_buf_is_valid(buf) then
      inline.clear(buf)
    end
  end
  inline_state = {}

  if global_state.augroup then
    vim.api.nvim_del_augroup_by_id(global_state.augroup)
    global_state.augroup = nil
  end

  global_state.enabled = false
end

return M
