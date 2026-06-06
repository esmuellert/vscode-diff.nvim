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

local function viewed_key(path, group)
  if not path or not group then
    return nil
  end
  return group .. ":" .. path
end

local function is_viewed(explorer, file)
  local data = file.data or {}
  local key = viewed_key(data.path, data.group)
  return key and explorer.viewed_files and explorer.viewed_files[key]
end

local function select_file(explorer, file)
  local current_win = vim.api.nvim_get_current_win()
  if explorer.winid and vim.api.nvim_win_is_valid(explorer.winid) then
    local line = find_node_line(explorer, file.data.path, file.data.group)
    if line then
      vim.api.nvim_set_current_win(explorer.winid)
      vim.api.nvim_win_set_cursor(explorer.winid, { line, 0 })
      vim.api.nvim_set_current_win(current_win)
    end
  end

  explorer.on_file_select(file.data)
end

local function notify_all_viewed()
  vim.notify("All files have been reviewed", vim.log.levels.INFO)
end

local function notify_no_other_unviewed()
  vim.notify("No other unreviewed files", vim.log.levels.INFO)
end

local function has_unviewed_file(explorer, files)
  for _, file in ipairs(files) do
    if not is_viewed(explorer, file) then
      return true
    end
  end
  return false
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

  if not has_unviewed_file(explorer, all_files) then
    notify_all_viewed()
    return
  end

  -- If no current path, select first unviewed file
  if not current_path then
    for _, file in ipairs(all_files) do
      if not is_viewed(explorer, file) then
        select_file(explorer, file)
        return
      end
    end
  end

  -- Find current index (match both path AND group for files in both staged/unstaged)
  local current_index = 0
  for i, file in ipairs(all_files) do
    if file.data.path == current_path and file.data.group == current_group then
      current_index = i
      break
    end
  end

  if current_index == 0 then
    for _, file in ipairs(all_files) do
      if not is_viewed(explorer, file) then
        select_file(explorer, file)
        return
      end
    end
  end

  local cycle = config.options.diff.cycle_next_file
  local search_count = cycle and (#all_files - 1) or (#all_files - current_index)
  for offset = 1, search_count do
    local index = current_index + offset
    if cycle then
      index = ((index - 1) % #all_files) + 1
    end
    local file = all_files[index]
    if file and not is_viewed(explorer, file) then
      vim.api.nvim_echo({}, false, {})
      select_file(explorer, file)
      return
    end
  end

  if cycle then
    notify_no_other_unviewed()
  else
    vim.api.nvim_echo({ { "Last unreviewed file", "WarningMsg" } }, false, {})
  end
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

  if not has_unviewed_file(explorer, all_files) then
    notify_all_viewed()
    return
  end

  -- If no current path, select last unviewed file
  if not current_path then
    for i = #all_files, 1, -1 do
      local file = all_files[i]
      if not is_viewed(explorer, file) then
        select_file(explorer, file)
        return
      end
    end
  end

  -- Find current index (match both path AND group for files in both staged/unstaged)
  local current_index = 0
  for i, file in ipairs(all_files) do
    if file.data.path == current_path and file.data.group == current_group then
      current_index = i
      break
    end
  end

  if current_index == 0 then
    for i = #all_files, 1, -1 do
      local file = all_files[i]
      if not is_viewed(explorer, file) then
        select_file(explorer, file)
        return
      end
    end
  end

  local cycle = config.options.diff.cycle_next_file
  local search_count = cycle and (#all_files - 1) or (current_index - 1)
  for offset = 1, search_count do
    local index = current_index - offset
    if cycle then
      index = ((index - 1) % #all_files) + 1
    end
    local file = all_files[index]
    if file and not is_viewed(explorer, file) then
      vim.api.nvim_echo({}, false, {})
      select_file(explorer, file)
      return
    end
  end

  if cycle then
    notify_no_other_unviewed()
  else
    vim.api.nvim_echo({ { "First unreviewed file", "WarningMsg" } }, false, {})
  end
end

-- Toggle viewed state for the file under the explorer cursor, or the current selected file from diff buffers.
function M.toggle_viewed(explorer)
  if not explorer or not explorer.tree then
    return
  end

  local path
  local group
  if explorer.bufnr and vim.api.nvim_get_current_buf() == explorer.bufnr then
    local node = explorer.tree:get_node()
    if not node or not node.data or node.data.type == "group" or node.data.type == "directory" then
      vim.notify("Mark reviewed is only available for files", vim.log.levels.WARN)
      return
    end
    path = node.data.path
    group = node.data.group
  else
    path = explorer.current_file_path
    group = explorer.current_file_group
  end

  local key = viewed_key(path, group)
  if not key then
    vim.notify("No file selected", vim.log.levels.WARN)
    return
  end

  explorer.viewed_files = explorer.viewed_files or {}
  if explorer.viewed_files[key] then
    explorer.viewed_files[key] = nil
  else
    explorer.viewed_files[key] = true
  end
  explorer.tree:render()
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

  -- Confirmation prompt
  local action_word = is_directory and "Discard all changes in " or (is_untracked and "Delete " or "Discard changes to ")
  local prompt = action_word .. display_name .. "?"
  local choice = vim.fn.confirm(prompt, "&Discard\n&Cancel", 2, "Warning")

  if choice == 1 then
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
