-- Panel setup for explorer and history sidebars
-- Shared utility used by both side-by-side and inline view engines
local M = {}

local lifecycle = require("codediff.ui.lifecycle")
local config = require("codediff.config")

-- Eagerly load explorer and history to avoid lazy require failures
-- when CWD changes in vim.schedule callbacks
local explorer_module = require("codediff.ui.explorer")
local history_module = require("codediff.ui.history")
local layout = require("codediff.ui.layout")

--- Create explorer sidebar for a diff tabpage
---@param tabpage number
---@param session_config SessionConfig
---@param original_win number
---@param modified_win number
function M.setup_explorer(tabpage, session_config, original_win, modified_win)
  if not (session_config.mode == "explorer" and session_config.explorer_data) then
    return
  end

  local explorer_config = config.options.explorer or {}
  local status_result = session_config.explorer_data.status_result

  local explorer_opts = {}
  if not session_config.git_root then
    explorer_opts.dir1 = session_config.original.absolute
    explorer_opts.dir2 = session_config.modified.absolute
  end
  if session_config.explorer_data.focus_file then
    explorer_opts.focus_file = session_config.explorer_data.focus_file
  end

  local explorer_obj =
    explorer_module.create(status_result, session_config.git_root, tabpage, nil, session_config.original_revision, session_config.modified_revision, explorer_opts)

  lifecycle.set_explorer(tabpage, explorer_obj)

  local initial_focus = explorer_config.initial_focus or "explorer"
  if initial_focus == "explorer" and explorer_obj and explorer_obj.winid and vim.api.nvim_win_is_valid(explorer_obj.winid) then
    vim.api.nvim_set_current_win(explorer_obj.winid)
  elseif initial_focus == "original" and vim.api.nvim_win_is_valid(original_win) then
    vim.api.nvim_set_current_win(original_win)
  elseif initial_focus == "modified" and vim.api.nvim_win_is_valid(modified_win) then
    vim.api.nvim_set_current_win(modified_win)
  end

  layout.arrange(tabpage)
end

--- Create history panel for a diff tabpage
---@param tabpage number
---@param session_config SessionConfig
---@param original_win number
---@param modified_win number
function M.setup_history(tabpage, session_config, original_win, modified_win)
  if not (session_config.mode == "history" and session_config.history_data) then
    return
  end

  local history_config = config.options.history or {}
  local commits = session_config.history_data.commits

  local history_obj = history_module.create(commits, session_config.git_root, tabpage, nil, {
    range = session_config.history_data.range,
    file_path = session_config.history_data.file_path,
    base_revision = session_config.history_data.base_revision,
    line_range = session_config.history_data.line_range,
  })

  lifecycle.set_explorer(tabpage, history_obj)

  local initial_focus = history_config.initial_focus or "history"
  if initial_focus == "history" and history_obj and history_obj.winid and vim.api.nvim_win_is_valid(history_obj.winid) then
    vim.api.nvim_set_current_win(history_obj.winid)
  elseif initial_focus == "original" and vim.api.nvim_win_is_valid(original_win) then
    vim.api.nvim_set_current_win(original_win)
  elseif initial_focus == "modified" and vim.api.nvim_win_is_valid(modified_win) then
    vim.api.nvim_set_current_win(modified_win)
  end

  layout.arrange(tabpage)
end

return M
