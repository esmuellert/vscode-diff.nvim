-- Keymaps for history panel
local config = require("codediff.config")
local tree_utils = require("codediff.ui.lib.tree_utils")
local set_keymap = require("codediff.ui.lifecycle.accessors").set_keymap

local M = {}

-- Setup keymaps for history panel
-- @param history: history object with tree, split, on_file_select, etc.
-- @param opts: { is_single_file_mode, file_path, git_root, load_commit_files, navigate_next, navigate_prev }
function M.setup(history, opts)
  local tree = history.tree
  local split = history.split
  local is_single_file_mode = opts.is_single_file_mode
  local load_commit_files = opts.load_commit_files

  local map_options = { noremap = true, silent = true, nowait = true }
  local history_keymaps = config.options.keymaps.history or {}

  -- Toggle expand/collapse or select file
  if history_keymaps.select then
    set_keymap("n", history_keymaps.select, function()
      local node = tree:get_node()
      if not node then
        return
      end

      if node.data and node.data.type == "commit" then
        if is_single_file_mode then
          -- Single file mode: directly show diff for the file at this commit
          local file_path = node.data.file_path or opts.file_path
          local file_data = {
            path = file_path,
            commit_hash = node.data.hash,
            git_root = opts.git_root,
          }
          history.on_file_select(file_data)
        elseif node:is_expanded() then
          node:collapse()
          tree:render()
        else
          load_commit_files(node)
        end
      elseif node.data and node.data.type == "directory" then
        if node:is_expanded() then
          node:collapse()
        else
          node:expand()
        end
        tree:render()
      elseif node.data and node.data.type == "file" then
        history.on_file_select(node.data)
      end
    end, vim.tbl_extend("force", map_options, { buffer = split.bufnr, desc = "Select/toggle entry" }))
  end

  -- Double-click support
  set_keymap("n", "<2-LeftMouse>", function()
    local node = tree:get_node()
    if not node then
      return
    end
    if node.data and node.data.type == "file" then
      history.on_file_select(node.data)
    elseif node.data and node.data.type == "directory" then
      if node:is_expanded() then
        node:collapse()
      else
        node:expand()
      end
      tree:render()
    elseif node.data and node.data.type == "commit" then
      if is_single_file_mode then
        local file_path = node.data.file_path or opts.file_path
        local file_data = {
          path = file_path,
          commit_hash = node.data.hash,
          git_root = opts.git_root,
        }
        history.on_file_select(file_data)
      elseif node:is_expanded() then
        node:collapse()
        tree:render()
      else
        load_commit_files(node)
      end
    end
  end, vim.tbl_extend("force", map_options, { buffer = split.bufnr, desc = "Select file" }))

  -- Note: next_file/prev_file keymaps are set via view/keymaps.lua:setup_all_keymaps()
  -- which uses set_tab_keymap to set them on all buffers including history panel

  -- Toggle view mode between list and tree
  if history_keymaps.toggle_view_mode then
    set_keymap("n", history_keymaps.toggle_view_mode, function()
      local history_config = config.options.history or {}
      local current_mode = history_config.view_mode or "list"
      local new_mode = (current_mode == "list") and "tree" or "list"

      config.options.history.view_mode = new_mode

      -- Reload files for all expanded commit nodes
      local root_nodes = tree:get_nodes() or {}
      for _, node in ipairs(root_nodes) do
        if node.data and node.data.type == "commit" and node:is_expanded() and node.data.files_loaded then
          node.data.files_loaded = false
          for _, child_id in ipairs(node:get_child_ids() or {}) do
            tree:remove_node(child_id)
          end
          load_commit_files(node)
        end
      end

      vim.notify("History view: " .. new_mode, vim.log.levels.INFO)
    end, vim.tbl_extend("force", map_options, { buffer = split.bufnr, desc = "Toggle list/tree view" }))
  end

  -- Refresh (R key) - re-fetch commits
  if history_keymaps.refresh then
    set_keymap("n", history_keymaps.refresh, function()
      local refresh_module = require("codediff.ui.history.refresh")
      refresh_module.refresh(history)
    end, vim.tbl_extend("force", map_options, { buffer = split.bufnr, desc = "Refresh history" }))
  end

  -- Fold keymaps (Vim-style: zo/zO/zc/zC/za/zA/zR/zM — directory nodes only)
  tree_utils.setup_fold_keymaps({
    tree = tree,
    keymaps = history_keymaps,
    bufnr = split.bufnr,
  })
end

return M
