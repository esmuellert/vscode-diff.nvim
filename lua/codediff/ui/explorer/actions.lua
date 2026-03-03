-- User actions for explorer (navigation, toggle, etc.)
local M = {}

local config = require("codediff.config")
local git = require("codediff.core.git")
local refresh_module = require("codediff.ui.explorer.refresh")
local layout = require("codediff.ui.layout")

-- Find line number for a file node by scanning the tree
-- Returns the line number or nil if not found
local function find_node_line(explorer, path, group)
  local line_count = vim.api.nvim_buf_line_count(explorer.bufnr)
  for line = 1, line_count do
    local node = explorer.tree:get_node(line)
    if node and node.data and node.data.path == path and node.data.group == group then
      return line
    end
  end
  return nil
end

-- Navigate to next file in explorer
function M.navigate_next(explorer)
  local all_files = refresh_module.get_all_files(explorer.tree)
  if #all_files == 0 then
    vim.notify("No files in explorer", vim.log.levels.WARN)
    return
  end

  -- Use tracked current file path and group
  local current_path = explorer.current_file_path
  local current_group = explorer.current_file_group

  -- If no current path, select first file
  if not current_path then
    local first_file = all_files[1]
    explorer.on_file_select(first_file.data)
    return
  end

  -- Find current index (match both path AND group for files in both staged/unstaged)
  local current_index = 0
  for i, file in ipairs(all_files) do
    if file.data.path == current_path and file.data.group == current_group then
      current_index = i
      break
    end
  end

  -- Get next file (wrap around if enabled)
  if current_index >= #all_files and not config.options.diff.cycle_next_file then
    vim.api.nvim_echo({ { string.format("Last file (%d of %d)", #all_files, #all_files), "WarningMsg" } }, false, {})
    return
  else
    vim.api.nvim_echo({}, false, {})
  end
  local next_index = current_index % #all_files + 1
  local next_file = all_files[next_index]

  -- Update tree selection visually (switch to explorer window temporarily)
  local current_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(explorer.winid) then
    local line = find_node_line(explorer, next_file.data.path, next_file.data.group)
    if line then
      vim.api.nvim_set_current_win(explorer.winid)
      vim.api.nvim_win_set_cursor(explorer.winid, { line, 0 })
      vim.api.nvim_set_current_win(current_win)
    end
  end

  -- Trigger file select
  explorer.on_file_select(next_file.data)
end

-- Navigate to previous file in explorer
function M.navigate_prev(explorer)
  local all_files = refresh_module.get_all_files(explorer.tree)
  if #all_files == 0 then
    vim.notify("No files in explorer", vim.log.levels.WARN)
    return
  end

  -- Use tracked current file path and group
  local current_path = explorer.current_file_path
  local current_group = explorer.current_file_group

  -- If no current path, select last file
  if not current_path then
    local last_file = all_files[#all_files]
    explorer.on_file_select(last_file.data)
    return
  end

  -- Find current index (match both path AND group for files in both staged/unstaged)
  local current_index = 0
  for i, file in ipairs(all_files) do
    if file.data.path == current_path and file.data.group == current_group then
      current_index = i
      break
    end
  end

  -- Get previous file (wrap around if enabled)
  if current_index <= 1 and not config.options.diff.cycle_next_file then
    vim.api.nvim_echo({ { string.format("First file (1 of %d)", #all_files), "WarningMsg" } }, false, {})
    return
  else
    vim.api.nvim_echo({}, false, {})
  end
  local prev_index = current_index - 2
  if prev_index < 0 then
    prev_index = #all_files + prev_index
  end
  prev_index = prev_index % #all_files + 1
  local prev_file = all_files[prev_index]

  -- Update tree selection visually (switch to explorer window temporarily)
  local current_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(explorer.winid) then
    local line = find_node_line(explorer, prev_file.data.path, prev_file.data.group)
    if line then
      vim.api.nvim_set_current_win(explorer.winid)
      vim.api.nvim_win_set_cursor(explorer.winid, { line, 0 })
      vim.api.nvim_set_current_win(current_win)
    end
  end

  -- Trigger file select
  explorer.on_file_select(prev_file.data)
end

-- Toggle explorer visibility (hide/show)
function M.toggle_visibility(explorer)
  if not explorer or not explorer.split then
    return
  end

  local tabpage = vim.api.nvim_get_current_tabpage()

  if explorer.is_hidden then
    explorer.split:show()
    explorer.is_hidden = false
    explorer.winid = explorer.split.winid

    vim.schedule(function()
      layout.arrange(tabpage)
    end)
  else
    explorer.split:hide()
    explorer.is_hidden = true

    vim.schedule(function()
      layout.arrange(tabpage)
    end)
  end
end

-- Toggle view mode between 'list' and 'tree'
function M.toggle_view_mode(explorer)
  if not explorer then
    return
  end

  local explorer_config = config.options.explorer or {}
  local current_mode = explorer_config.view_mode or "list"
  local new_mode = (current_mode == "list") and "tree" or "list"

  -- Update config
  config.options.explorer.view_mode = new_mode

  -- Refresh to rebuild tree with new mode
  refresh_module.refresh(explorer)

  vim.notify("Explorer view: " .. new_mode, vim.log.levels.INFO)
end

-- Toggle visibility of a group (staged/unstaged/conflicts)
function M.toggle_group(explorer, group_name)
  if not explorer or not explorer.visible_groups then
    return
  end

  explorer.visible_groups[group_name] = not explorer.visible_groups[group_name]
  refresh_module.refresh(explorer)

  local state = explorer.visible_groups[group_name] and "shown" or "hidden"
  local label = ({ staged = "Staged Changes", unstaged = "Changes", conflicts = "Merge Changes" })[group_name] or group_name
  vim.notify(label .. ": " .. state, vim.log.levels.INFO)
end

-- Stage/unstage a file by path and group (lower-level function)
-- This can be called from anywhere with explicit path and group
-- @param git_root: git repository root
-- @param file_path: relative path to file
-- @param group: "staged", "unstaged", or "conflicts"
-- @return boolean: true if operation was initiated
function M.toggle_stage_file(git_root, file_path, group)
  if not git_root then
    vim.notify("Stage/unstage only available in git mode", vim.log.levels.WARN)
    return false
  end

  if not file_path or not group then
    return false
  end

  -- Guard: only stageable groups
  if group ~= "staged" and group ~= "unstaged" and group ~= "conflicts" then
    return false
  end

  if group == "staged" then
    -- Unstage file
    git.unstage_file(git_root, file_path, function(err)
      if err then
        vim.schedule(function()
          vim.notify(err, vim.log.levels.ERROR)
        end)
      end
    end)
  elseif group == "unstaged" then
    -- Stage file
    git.stage_file(git_root, file_path, function(err)
      if err then
        vim.schedule(function()
          vim.notify(err, vim.log.levels.ERROR)
        end)
      end
    end)
  elseif group == "conflicts" then
    -- Stage conflict file (marks as resolved)
    git.stage_file(git_root, file_path, function(err)
      if err then
        vim.schedule(function()
          vim.notify(err, vim.log.levels.ERROR)
        end)
      end
    end)
  end

  return true
end

-- Stage/unstage all files under a directory
-- @param git_root: git repository root
-- @param dir_path: relative directory path
-- @param group: "staged" or "unstaged"
local function toggle_stage_directory(git_root, dir_path, group)
  if group == "staged" then
    -- Unstage directory
    git.unstage_file(git_root, dir_path, function(err)
      if err then
        vim.schedule(function()
          vim.notify(err, vim.log.levels.ERROR)
        end)
      end
    end)
  elseif group == "unstaged" then
    -- Stage directory
    git.stage_file(git_root, dir_path, function(err)
      if err then
        vim.schedule(function()
          vim.notify(err, vim.log.levels.ERROR)
        end)
      end
    end)
  end
end

-- Stage/unstage toggle for the selected entry in explorer (file or directory)
function M.toggle_stage_entry(explorer, tree)
  if not explorer or not explorer.git_root then
    vim.notify("Stage/unstage only available in git mode", vim.log.levels.WARN)
    return
  end

  local node = tree:get_node()
  if not node or not node.data or node.data.type == "group" then
    return
  end

  local entry_type = node.data.type
  local group = node.data.group

  if entry_type == "directory" then
    -- Directory uses dir_path, not path
    local dir_path = node.data.dir_path
    if dir_path then
      toggle_stage_directory(explorer.git_root, dir_path, group)
    end
  else
    -- File uses path
    local path = node.data.path
    if path then
      M.toggle_stage_file(explorer.git_root, path, group)
    end
  end
end

-- Toggle diff layout between 'side-by-side' and 'inline'
function M.toggle_layout(explorer)
  local lifecycle = require("codediff.ui.lifecycle")
  local layout_manager = require("codediff.ui.layout")

  local tabpage = explorer and explorer.tabpage or vim.api.nvim_get_current_tabpage()
  local session = lifecycle.get_session(tabpage)

  if not session then
    vim.notify("No active diff session", vim.log.levels.WARN)
    return
  end

  -- Don't toggle in conflict mode
  if session.result_win and vim.api.nvim_win_is_valid(session.result_win) then
    vim.notify("Cannot toggle layout in conflict mode", vim.log.levels.WARN)
    return
  end

  local current_layout = session.layout or "side-by-side"
  local new_layout = current_layout == "inline" and "side-by-side" or "inline"

  -- Update global config so subsequent file selections use the new layout
  config.options.diff.layout = new_layout

  -- Build session_config from current session state for re-rendering
  local session_config = {
    mode = session.mode,
    git_root = session.git_root,
    original_path = session.original_path,
    modified_path = session.modified_path,
    original_revision = session.original_revision,
    modified_revision = session.modified_revision,
  }

  local is_placeholder = (session.original_path == "" and session.modified_path == "")

  if new_layout == "side-by-side" then
    -- inline → side-by-side: create new window for the original side
    local modified_win = session.modified_win
    if not modified_win or not vim.api.nvim_win_is_valid(modified_win) then
      return
    end

    -- Clear inline decorations from the modified buffer
    local inline_mod = require("codediff.ui.inline")
    if session.modified_bufnr and vim.api.nvim_buf_is_valid(session.modified_bufnr) then
      inline_mod.clear(session.modified_bufnr)
    end
    lifecycle.clear_highlights(session.modified_bufnr)

    -- Create original window (split on the appropriate side)
    local split_cmd = config.options.diff.original_position == "right" and "rightbelow vsplit" or "leftabove vsplit"
    vim.api.nvim_set_current_win(modified_win)
    vim.cmd(split_cmd)
    local original_win = vim.api.nvim_get_current_win()
    vim.w[original_win].codediff_restore = 1

    -- Update session window state
    session.original_win = original_win
    session.layout = nil -- nil means side-by-side (default)

    if is_placeholder then
      -- Load scratch buffer into the new original window
      local orig_scratch = vim.api.nvim_create_buf(false, true)
      vim.bo[orig_scratch].buftype = "nofile"
      vim.api.nvim_win_set_buf(original_win, orig_scratch)
      session.original_bufnr = orig_scratch
      layout_manager.arrange(tabpage)
    else
      vim.schedule(function()
        require("codediff.ui.view.side_by_side").update(tabpage, session_config, false)
        layout_manager.arrange(tabpage)
      end)
    end
  else
    -- side-by-side → inline: close original_win, keep modified_win
    local original_win = session.original_win
    local modified_win = session.modified_win

    if not modified_win or not vim.api.nvim_win_is_valid(modified_win) then
      return
    end

    -- Clear diff highlights from both buffers
    lifecycle.clear_highlights(session.original_bufnr)
    lifecycle.clear_highlights(session.modified_bufnr)

    -- Disable scrollbind on modified window before closing original
    if vim.api.nvim_win_is_valid(modified_win) then
      vim.wo[modified_win].scrollbind = false
    end

    -- Close original window if it is distinct from modified
    if original_win and vim.api.nvim_win_is_valid(original_win) and original_win ~= modified_win then
      vim.api.nvim_set_current_win(modified_win)
      pcall(vim.api.nvim_win_close, original_win, false)
    end

    -- Collapse session to single window
    session.original_win = modified_win
    session.layout = "inline"

    if is_placeholder then
      layout_manager.arrange(tabpage)
    else
      vim.schedule(function()
        require("codediff.ui.view.inline_view").update(tabpage, session_config, false)
        layout_manager.arrange(tabpage)
      end)
    end
  end

  vim.notify("Layout: " .. new_layout, vim.log.levels.INFO)
end

-- Stage all files
function M.stage_all(explorer)
  if not explorer or not explorer.git_root then
    vim.notify("Stage all only available in git mode", vim.log.levels.WARN)
    return
  end

  git.stage_all(explorer.git_root, function(err)
    if err then
      vim.schedule(function()
        vim.notify(err, vim.log.levels.ERROR)
      end)
    end
  end)
end

-- Unstage all files
function M.unstage_all(explorer)
  if not explorer or not explorer.git_root then
    vim.notify("Unstage all only available in git mode", vim.log.levels.WARN)
    return
  end

  git.unstage_all(explorer.git_root, function(err)
    if err then
      vim.schedule(function()
        vim.notify(err, vim.log.levels.ERROR)
      end)
    end
  end)
end

-- Restore/discard changes to the selected file or directory
function M.restore_entry(explorer, tree)
  if not explorer or not explorer.git_root then
    vim.notify("Restore only available in git mode", vim.log.levels.WARN)
    return
  end

  local node = tree:get_node()
  if not node or not node.data or node.data.type == "group" then
    return
  end

  local entry_type = node.data.type
  local is_directory = entry_type == "directory"
  local entry_path = is_directory and node.data.dir_path or node.data.path
  local group = node.data.group
  local status = node.data.status

  if not entry_path then
    return
  end

  -- Only restore unstaged changes (working tree changes)
  if group ~= "unstaged" then
    vim.notify("Can only restore unstaged changes", vim.log.levels.WARN)
    return
  end

  -- For directories, we don't have a single status, so assume mixed
  -- For files, check if untracked
  local is_untracked = not is_directory and status == "??"
  local display_name = entry_path .. (is_directory and "/" or "")

  -- Two-line confirmation prompt
  local action_word = is_directory and "Discard all changes in " or (is_untracked and "Delete " or "Discard changes to ")
  vim.api.nvim_echo({
    { action_word, "WarningMsg" },
    { display_name, "WarningMsg" },
    { "?\n", "WarningMsg" },
    { "(D)", "WarningMsg" },
    { is_untracked and "elete, " or "iscard, ", "WarningMsg" },
    { "[C]", "WarningMsg" },
    { "ancel: ", "WarningMsg" },
  }, false, {})

  local char = vim.fn.getcharstr():lower()

  if char == "d" then
    if is_untracked then
      -- Delete untracked file/directory
      git.delete_untracked(explorer.git_root, entry_path, function(err)
        if err then
          vim.schedule(function()
            vim.notify(err, vim.log.levels.ERROR)
          end)
        end
      end)
    elseif is_directory then
      -- Directory may contain both tracked and untracked files
      -- Run git restore for tracked changes, then git clean for untracked
      git.restore_file(explorer.git_root, entry_path, explorer.base_revision, function(restore_err)
        git.delete_untracked(explorer.git_root, entry_path, function(clean_err)
          if restore_err and clean_err then
            vim.schedule(function()
              vim.notify("Failed to restore: " .. restore_err, vim.log.levels.ERROR)
            end)
          end
        end)
      end)
    else
      -- Restore tracked file
      git.restore_file(explorer.git_root, entry_path, explorer.base_revision, function(err)
        if err then
          vim.schedule(function()
            vim.notify(err, vim.log.levels.ERROR)
          end)
        end
      end)
    end
  end
  vim.cmd("echo ''") -- Clear prompt
end

return M
