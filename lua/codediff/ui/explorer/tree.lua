-- Tree data structure building for explorer
-- Handles creating the tree hierarchy from git status
local M = {}

local Tree = require("codediff.ui.lib.tree")
local config = require("codediff.config")
local filter = require("codediff.ui.explorer.filter")
local line_stats = require("codediff.ui.explorer.line_stats")
local nodes = require("codediff.ui.explorer.nodes")

-- Filter files based on explorer.file_filter config
-- Returns files that should be shown (not ignored)
local function filter_files(files)
  local explorer_config = config.options.explorer or {}
  local file_filter = explorer_config.file_filter or {}
  local ignore_patterns = file_filter.ignore or {}

  return filter.apply(files, ignore_patterns)
end

local function create_group_node(label, name, files, children)
  return Tree.Node({
    text = string.format("%s (%d)", label, #files),
    data = {
      type = "group",
      name = name,
      label = label,
      file_count = #files,
      stats = line_stats.sum(files),
      files = files,
    },
  }, children)
end

-- Create tree data structure from git status result
function M.create_tree_data(status_result, git_root, base_revision, is_dir_mode, visible_groups)
  local explorer_config = config.options.explorer or {}
  local view_mode = explorer_config.view_mode or "list"
  visible_groups = visible_groups or explorer_config.visible_groups or {}

  -- Filter merge artifacts and apply file filter
  local unstaged = nodes.filter_merge_artifacts(filter_files(status_result.unstaged))
  local staged = nodes.filter_merge_artifacts(filter_files(status_result.staged))
  local conflicts = status_result.conflicts and nodes.filter_merge_artifacts(filter_files(status_result.conflicts)) or {}

  local create_nodes = (view_mode == "tree") and nodes.create_tree_file_nodes or nodes.create_file_nodes
  local unstaged_nodes = create_nodes(unstaged, git_root, "unstaged")
  local staged_nodes = create_nodes(staged, git_root, "staged")
  local conflict_nodes = create_nodes(conflicts, git_root, "conflicts")

  if is_dir_mode or base_revision then
    -- Dir or revision mode: single group showing all changes.
    -- `get_diff_revision(s)` and `dir.diff_directories` populate `unstaged`;
    -- `get_diff_staged` (--staged, #352) populates `staged`. Pick whichever
    -- has entries — no need for extra flags.
    if #staged > 0 then
      return {
        create_group_node("Staged Changes", "staged", staged, staged_nodes),
      }
    end
    return {
      create_group_node("Changes", "unstaged", unstaged, unstaged_nodes),
    }
  else
    -- Status mode: separate conflicts/staged/unstaged groups
    local tree_nodes = {}

    -- Conflicts first (most important)
    if #conflict_nodes > 0 and visible_groups.conflicts ~= false then
      table.insert(tree_nodes, create_group_node("Merge Changes", "conflicts", conflicts, conflict_nodes))
    end

    -- Unstaged changes
    if visible_groups.unstaged ~= false then
      table.insert(tree_nodes, create_group_node("Changes", "unstaged", unstaged, unstaged_nodes))
    end

    -- Staged changes
    if visible_groups.staged ~= false then
      table.insert(tree_nodes, create_group_node("Staged Changes", "staged", staged, staged_nodes))
    end

    return tree_nodes
  end
end

return M
