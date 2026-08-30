-- Auto-refresh and refresh logic for explorer
local M = {}

local config = require("codediff.config")
local tree_module = require("codediff.ui.explorer.tree")
local welcome = require("codediff.ui.welcome")
-- Setup auto-refresh triggers for explorer.
-- Returns a cleanup function that should be called when the explorer is destroyed.
--
-- Runs an explicit 500ms poll while the explorer is visible. This replaces the
-- earlier `.git/` fs_event watcher, which had a self-triggering loop: our own
-- `git status` briefly created `.git/index.lock`, waking the watcher and
-- firing another refresh. That loop delivered ~2 refreshes/second by
-- accident; #480 killed it by filtering `*.lock` events, but the filter also
-- suppressed the events that signal external working-tree changes (e.g. a
-- terminal `touch new_file.txt`), so those stopped showing up until the user
-- focused the explorer. The formal poll restores instant detection with the
-- same worst-case CPU profile as the old bug, minus the self-triggering
-- mechanics, and lets us drop the whole watcher plumbing.
function M.setup_auto_refresh(explorer, tabpage)
  local explorer_config = config.options.explorer or {}
  if explorer_config.auto_refresh == false then
    explorer._cleanup_auto_refresh = function() end
    return
  end

  local poll_interval_ms = 500

  local uv = vim.uv or vim.loop
  local poll_timer = uv.new_timer()
  local group = vim.api.nvim_create_augroup("CodeDiffExplorerRefresh_" .. tabpage, { clear = true })

  local function cleanup()
    if poll_timer then
      pcall(function()
        poll_timer:stop()
      end)
      pcall(function()
        poll_timer:close()
      end)
      poll_timer = nil
    end
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end

  explorer._cleanup_auto_refresh = cleanup

  local function tick()
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      return
    end
    if explorer.is_hidden then
      return
    end
    -- Skip ticks whose target directory is gone or not yet a git repo.
    -- This closes two race windows that used to emit a noisy
    -- `vim.notify("Failed to refresh: fatal: not a git repository ...", ERROR)`
    -- to the user (and to test stderr):
    --   1. A tab is closing but the timer is still scheduled between the
    --      `after_each`-triggered `rm -rf repo` and the TabClosed autocmd
    --      running the cleanup — a stale tick fires against the deleted
    --      directory.
    --   2. First tick after :CodeDiff on a slow filesystem (Windows CI):
    --      the explorer opens before `git init` has finished writing
    --      `.git/`, and the first 500ms tick beats the initialization.
    -- Either way, a poll aimed at a directory that isn't a git repo now is
    -- correctly a no-op — the next tick (500ms later) either finds the repo
    -- or the tab is gone. A user who `rm -rf`s their own repo behind the
    -- explorer gets silence, not an error dialog.
    local git_root = explorer.git_root
    if git_root and git_root ~= "" then
      if vim.fn.isdirectory(git_root) == 0 then
        return
      end
      -- `.git` may be either a directory (normal repo) or a file (worktrees,
      -- submodules — `gitdir: <path>` pointer). Missing on both counts means
      -- the directory exists but isn't a repo yet.
      local dot_git = git_root .. "/.git"
      if vim.fn.isdirectory(dot_git) == 0 and vim.fn.filereadable(dot_git) == 0 then
        return
      end
    end
    M.refresh(explorer)
    local auto_refresh = require("codediff.ui.auto_refresh")
    auto_refresh.sync_mutable_buffers(tabpage)
  end

  if poll_timer then
    poll_timer:start(poll_interval_ms, poll_interval_ms, vim.schedule_wrap(tick))
  end

  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    pattern = tostring(tabpage),
    callback = cleanup,
  })

  return cleanup
end

-- Collect collapsed state from tree (groups and directories that user manually collapsed)
--- Walk every group and directory node beneath `root_nodes`, calling `visit`
--- with the node and the key it is remembered by.
--- @param visit fun(node: table, key: string)
local function walk_collapsible(tree, root_nodes, visit)
  local function walk(node)
    if not node.data then
      return
    end
    local node_type = node.data.type
    if node_type ~= "group" and node_type ~= "directory" then
      return
    end
    -- Directories are keyed by path, groups by name.
    local key = node.data.path or node.data.name
    if key then
      visit(node, key)
    end
    if node:has_children() then
      for _, child_id in ipairs(node:get_child_ids()) do
        local child = tree:get_node(child_id)
        if child then
          walk(child)
        end
      end
    end
  end

  for _, node in ipairs(root_nodes) do
    walk(node)
  end
end

--- Which collapsible nodes are collapsed, keyed for restoring later.
local function collect_collapsed_state(tree)
  local collapsed = {}
  walk_collapsible(tree, tree:get_nodes(), function(node, key)
    if not node:is_expanded() then
      collapsed[key] = true
    end
  end)
  return collapsed
end

--- Re-collapse whatever was collapsed before the tree was rebuilt.
local function restore_collapsed_state(tree, collapsed, root_nodes)
  walk_collapsible(tree, root_nodes, function(node, key)
    if collapsed[key] then
      node:collapse()
    end
  end)
end

-- Rebuild the explorer tree from a status_result and re-render, honoring the
-- current group visibility. Runs synchronously (no vim.schedule), so callers in
-- a normal context — e.g. toggling a group — get an immediately consistent tree.
--- The reviewed file's slot in its group, read off the status from before the
--- refresh. file_to_reselect needs it to find whatever takes that slot.
--- @param explorer table
--- @return number|nil
local function reviewed_file_index(explorer)
  local group = explorer.current_file_group
  if not group then
    return nil
  end
  for i, f in ipairs((explorer.status_result or {})[group] or {}) do
    if f.path == explorer.current_file_path then
      return i
    end
  end
  return nil
end

--- Forget which file was being reviewed, panel selection included.
--- @param explorer table
local function clear_current_file(explorer)
  explorer.current_file_path = nil
  explorer.current_file_group = nil
  explorer.current_selection = nil
  if explorer.clear_selection then
    explorer.clear_selection()
  end
end

--- Which file the explorer should show after a refresh, and in which group.
---
--- Prefer the same group the reviewer was in: hunk staging leaves the file
--- where it was. When the file left that group entirely -- fully staged or
--- unstaged -- take whatever now occupies its slot there, so staging walks
--- down the unstaged list instead of chasing the file into the staged one
--- (#347). Only if the group has nothing left does the search follow the file.
---
--- @param explorer table
--- @param status_result table
--- @param prev_index number? The file's slot in its group before the refresh
--- @return table|nil file, string|nil group
local function file_to_reselect(explorer, status_result, prev_index)
  local group_lists = {
    unstaged = status_result.unstaged,
    staged = status_result.staged,
    conflicts = status_result.conflicts,
  }
  local current_group = explorer.current_file_group

  local function search(files, group_name)
    for _, f in ipairs(files or {}) do
      if f.path == explorer.current_file_path then
        return f, group_name
      end
    end
    return nil, nil
  end

  if current_group then
    local found, group = search(group_lists[current_group], current_group)
    if found then
      return found, group
    end
  end

  if current_group and prev_index then
    local same_group = group_lists[current_group]
    if same_group and #same_group > 0 then
      return same_group[math.min(prev_index, #same_group)], current_group
    end
  end

  for _, group_name in ipairs({ "conflicts", "unstaged", "staged" }) do
    local found, group = search(status_result[group_name], group_name)
    if found then
      return found, group
    end
  end

  return nil, nil
end

local function rebuild_tree(explorer, status_result, collapsed_state)
  local root_nodes = tree_module.create_tree_data(status_result, explorer.git_root, explorer.base_revision, not explorer.git_root, explorer.visible_groups)

  -- Expand all groups
  for _, node in ipairs(root_nodes) do
    node:expand()
  end

  -- Update tree
  explorer.tree:set_nodes(root_nodes)

  -- For tree mode, expand directories after setting nodes
  local explorer_config = config.options.explorer or {}
  if explorer_config.view_mode == "tree" then
    local function expand_all_dirs(parent_node)
      if not parent_node:has_children() then
        return
      end
      for _, child_id in ipairs(parent_node:get_child_ids()) do
        local child = explorer.tree:get_node(child_id)
        if child and child.data and child.data.type == "directory" then
          child:expand()
          expand_all_dirs(child)
        end
      end
    end
    for _, node in ipairs(root_nodes) do
      expand_all_dirs(node)
    end
  end

  -- Restore user's collapsed state (must be after expand_all_dirs)
  restore_collapsed_state(explorer.tree, collapsed_state, root_nodes)

  explorer.tree:render()
end

-- Refresh explorer with updated git status
function M.refresh(explorer)
  local git = require("codediff.core.git")

  -- Skip refresh if explorer is hidden
  if explorer.is_hidden then
    return
  end

  -- Verify window is still valid before accessing
  if not vim.api.nvim_win_is_valid(explorer.winid) then
    return
  end

  -- Collect collapsed state before async operation
  local collapsed_state = collect_collapsed_state(explorer.tree)

  local function process_result(err, status_result)
    vim.schedule(function()
      if err then
        vim.notify("Failed to refresh: " .. err, vim.log.levels.ERROR)
        return
      end

      -- Skip the whole downstream refresh (tree rebuild, re-selection,
      -- mutable-buffer sync) when the status is identical to the previous
      -- tick. `git status` still runs every tick so coverage is unchanged;
      -- this only avoids UI churn (tree re-render, re-selection re-running
      -- layout.arrange, extmark rewrites) that would flicker the interface
      -- and can interrupt the user (manual pane sizes reset, tree flatten
      -- flake, cursor jumps) even though nothing actually changed.
      if vim.deep_equal(status_result, explorer.status_result) then
        return
      end

      -- Rebuild tree nodes (honors group visibility) and re-render.
      rebuild_tree(explorer, status_result, collapsed_state)

      -- Read before status_result is replaced below.
      local prev_index = reviewed_file_index(explorer)
      explorer.status_result = status_result

      local show_welcome_page = require("codediff.ui.explorer.render").show_welcome_page

      -- Show welcome page when all files are clean (skip if already showing)
      local total_files = #(status_result.unstaged or {}) + #(status_result.staged or {}) + #(status_result.conflicts or {})
      if total_files == 0 then
        local lifecycle = require("codediff.ui.lifecycle")
        local session = lifecycle.get_session(explorer.tabpage)
        local already_welcome = session and welcome.is_welcome_buffer(session.modified_bufnr)
        clear_current_file(explorer)
        if not already_welcome then
          show_welcome_page(explorer)
        end
      end

      -- Re-select the currently viewed file after refresh.
      -- Search all file children across all groups for the current file.
      -- If found (possibly in a new group), call on_file_select to update diff panes.
      -- If not found (committed/removed), show welcome page.
      if explorer.current_file_path and total_files > 0 then
        local found_file, found_group = file_to_reselect(explorer, status_result, prev_index)
        if found_file then
          -- on_file_select dedupes; no_jump keeps the cursor where it is,
          -- since this is a refresh rather than a click.
          explorer.on_file_select({
            path = found_file.path,
            old_path = found_file.old_path,
            status = found_file.status,
            git_root = explorer.git_root,
            group = found_group,
          }, { no_jump = true })
        else
          -- Committed or removed.
          clear_current_file(explorer)
          show_welcome_page(explorer)
        end
      end
    end)
  end

  -- Use appropriate function based on mode
  if not explorer.git_root then
    -- Dir mode: re-scan directories
    local dir_mod = require("codediff.core.dir")
    local diff = dir_mod.diff_directories(explorer.dir1, explorer.dir2)
    process_result(nil, diff.status_result)
  elseif explorer.target_revision == ":0" then
    -- Staged-only mode (--staged): index vs base_revision. `git diff base :0`
    -- isn't a valid rev-pair; use `git diff --cached base` instead.
    git.get_diff_staged(explorer.base_revision, explorer.git_root, process_result, explorer.pathspec)
  elseif explorer.base_revision and explorer.target_revision and explorer.target_revision ~= "WORKING" then
    git.get_diff_revisions_with_line_stats(explorer.base_revision, explorer.target_revision, explorer.git_root, process_result, explorer.pathspec)
  elseif explorer.base_revision then
    git.get_diff_revision_with_line_stats(explorer.base_revision, explorer.git_root, process_result, explorer.pathspec)
  else
    git.get_status_with_line_stats(explorer.git_root, process_result, explorer.pathspec)
  end
end

-- Rebuild the tree synchronously from the cached status_result. Used when only
-- group visibility changed (gs/gu): hiding or showing a group needs no new git
-- data, so we re-render immediately from the last known status instead of
-- waiting for an async git refresh. This keeps the tree — and navigation, which
-- reads it — consistent the moment visibility toggles.
function M.rebuild_from_cache(explorer)
  if not explorer or not explorer.winid or not vim.api.nvim_win_is_valid(explorer.winid) then
    return
  end
  local status_result = explorer.status_result
  if not status_result then
    -- No cached status yet; fall back to a full (async) refresh.
    M.refresh(explorer)
    return
  end
  local collapsed_state = collect_collapsed_state(explorer.tree)
  rebuild_tree(explorer, status_result, collapsed_state)
end

-- Get flat list of all files from tree (unstaged + staged)
-- Handles both list mode (flat) and tree mode (nested directories)
function M.get_all_files(tree)
  local files = {}

  -- Recursively collect files from a node and its children
  local function collect_files(parent_node)
    if not parent_node:has_children() then
      return
    end
    if not parent_node:is_expanded() then
      return
    end

    for _, child_id in ipairs(parent_node:get_child_ids()) do
      local node = tree:get_node(child_id)
      if node and node.data then
        if node.data.type == "directory" then
          -- Recurse into directory (tree mode)
          collect_files(node)
        elseif not node.data.type then
          -- It's a file (no type means file node)
          table.insert(files, {
            node = node,
            data = node.data,
          })
        end
      end
    end
  end

  local nodes = tree:get_nodes()
  for _, group_node in ipairs(nodes) do
    collect_files(group_node)
  end

  return files
end

return M
