-- UI rendering for file history panel (create split, tree, keymaps)
local M = {}

local Tree = require("codediff.ui.lib.tree")
local Split = require("codediff.ui.lib.split")
local config = require("codediff.config")
local git = require("codediff.core.git")
local nodes_module = require("codediff.ui.history.nodes")
local keymaps_module = require("codediff.ui.history.keymaps")
local layout = require("codediff.ui.layout")

-- Build tree nodes from commits list (shared between create and refresh)
function M.build_tree_nodes(commits, git_root, opts)
  local base_revision = opts and opts.base_revision

  -- Calculate max widths for alignment
  local max_files = 0
  local max_insertions = 0
  local max_deletions = 0
  for _, commit in ipairs(commits) do
    if commit.files_changed > max_files then
      max_files = commit.files_changed
    end
    if commit.insertions > max_insertions then
      max_insertions = commit.insertions
    end
    if commit.deletions > max_deletions then
      max_deletions = commit.deletions
    end
  end
  local max_files_width = #tostring(max_files)
  local max_ins_width = #tostring(max_insertions)
  local max_del_width = #tostring(max_deletions)

  local tree_nodes = {}

  -- Build title based on context
  local title_text
  if opts and opts.file_path and opts.file_path ~= "" then
    local filename = opts.file_path:match("([^/]+)$") or opts.file_path
    title_text = "File History: " .. filename .. " (" .. #commits .. ")"
  elseif opts and opts.range and opts.range ~= "" then
    title_text = "Commit History: " .. opts.range .. " (" .. #commits .. ")"
  else
    title_text = "Commit History (" .. #commits .. ")"
  end

  if base_revision then
    title_text = title_text .. " [base: " .. base_revision .. "]"
  end

  tree_nodes[#tree_nodes + 1] = Tree.Node({
    id = "title",
    text = title_text,
    data = {
      type = "title",
      title = title_text,
    },
  })

  for _, commit in ipairs(commits) do
    tree_nodes[#tree_nodes + 1] = Tree.Node({
      id = "commit:" .. commit.hash,
      text = commit.subject,
      data = {
        type = "commit",
        hash = commit.hash,
        short_hash = commit.short_hash,
        author = commit.author,
        date = commit.date,
        date_relative = commit.date_relative,
        subject = commit.subject,
        ref_names = commit.ref_names,
        files_changed = commit.files_changed,
        insertions = commit.insertions,
        deletions = commit.deletions,
        file_count = commit.files_changed,
        git_root = git_root,
        files_loaded = false,
        file_path = commit.file_path or opts.file_path,
        max_files_width = max_files_width,
        max_ins_width = max_ins_width,
        max_del_width = max_del_width,
      },
    })
  end

  return tree_nodes
end

-- Create file history panel
-- commits: array of commit objects from git.get_commit_list
-- git_root: absolute path to git repository root
-- tabpage: tabpage handle
-- width: optional width override
-- opts: { range, path, ... } original options
function M.create(commits, git_root, tabpage, width, opts)
  opts = opts or {}
  local base_revision = opts.base_revision
  local line_range = opts.line_range

  -- Get history panel position and size from config (separate from explorer)
  local history_config = config.options.history or {}
  local position = history_config.position or "bottom"
  local size
  local text_width

  if position == "bottom" then
    size = history_config.height or 15
    text_width = vim.o.columns
  else
    size = width or history_config.width or 40
    text_width = size
  end

  -- Create split window for history panel
  local split = Split({
    relative = "editor",
    position = position,
    size = size,
    buf_options = {
      modifiable = false,
      readonly = true,
      filetype = "codediff-history",
    },
    win_options = {
      number = false,
      relativenumber = false,
      cursorline = true,
      wrap = false,
      signcolumn = "no",
      foldcolumn = "0",
      spell = false,
    },
  })

  split:mount()
  pcall(vim.api.nvim_buf_set_name, split.bufnr, "CodeDiff History [" .. tabpage .. "]")

  -- Track selected commit/file and reviewed files for highlighting
  local selected_commit = nil
  local selected_file = nil
  local viewed_files = {}

  -- Check if single file mode
  local is_single_file_mode = opts.file_path and opts.file_path ~= ""

  -- Build initial tree with commit nodes (files will be loaded on expand)
  local tree_nodes = M.build_tree_nodes(commits, git_root, opts)
  local first_commit_node = nil -- Track first commit for auto-expand
  for _, node in ipairs(tree_nodes) do
    if node.data and node.data.type == "commit" and not first_commit_node then
      first_commit_node = node
    end
  end

  local tree = Tree({
    bufnr = split.bufnr,
    nodes = tree_nodes,
    prepare_node = function(node)
      local current_width = text_width
      if split.winid and vim.api.nvim_win_is_valid(split.winid) then
        current_width = vim.api.nvim_win_get_width(split.winid)
      end
      return nodes_module.prepare_node(node, current_width, selected_commit, selected_file, is_single_file_mode, viewed_files)
    end,
  })

  tree:render()

  -- Create history panel object
  local history = {
    split = split,
    tree = tree,
    bufnr = split.bufnr,
    winid = split.winid,
    git_root = git_root,
    commits = commits,
    opts = opts,
    on_file_select = nil,
    current_commit = nil,
    current_file = nil,
    current_selection = nil,
    viewed_files = viewed_files,
    is_hidden = false,
    is_single_file_mode = is_single_file_mode,
  }

  -- Load files for a commit and update its children
  local function load_commit_files(commit_node, callback)
    local data = commit_node.data

    -- Skip non-commit nodes (e.g., title node)
    if not data or data.type ~= "commit" then
      if callback then
        callback()
      end
      return
    end

    if data.files_loaded then
      -- Files already loaded, just expand
      commit_node:expand()
      tree:render()
      if callback then
        callback()
      end
      return
    end

    git.get_commit_files(data.hash, git_root, function(err, files)
      if err then
        vim.schedule(function()
          vim.notify("Failed to load commit files: " .. err, vim.log.levels.ERROR)
        end)
        return
      end

      vim.schedule(function()
        -- Apply file_filter.ignore patterns (same as explorer view)
        local filter = require("codediff.ui.explorer.filter")
        local explorer_config = config.options.explorer or {}
        local file_filter = explorer_config.file_filter or {}
        local ignore_patterns = file_filter.ignore or {}
        files = filter.apply(files, ignore_patterns)

        -- Create file nodes based on view_mode
        local history_config = config.options.history or {}
        local view_mode = history_config.view_mode or "list"

        local file_nodes
        if view_mode == "tree" then
          file_nodes = nodes_module.create_tree_file_nodes(files, data.hash, git_root)
        else
          file_nodes = nodes_module.create_list_file_nodes(files, data.hash, git_root)
        end

        -- Update node with children
        data.files_loaded = true
        data.file_count = #files

        -- Tree doesn't have a direct "add children" API, so we need to rebuild
        -- For now, we'll use set_nodes on the commit node
        for _, file_node in ipairs(file_nodes) do
          tree:add_node(file_node, commit_node:get_id())
        end

        -- Auto-expand all directory nodes in tree mode
        if view_mode == "tree" then
          local function expand_directories(node_ids)
            for _, node_id in ipairs(node_ids) do
              local node = tree:get_node(node_id)
              if node and node.data and node.data.type == "directory" then
                node:expand()
                expand_directories(node:get_child_ids() or {})
              end
            end
          end
          expand_directories(commit_node:get_child_ids() or {})
        end

        commit_node:expand()
        tree:render()

        if callback then
          callback()
        end
      end)
    end)
  end

  -- File selection callback
  local function on_file_select(file_data, opts)
    opts = opts or {}
    local view = require("codediff.ui.view")
    local lifecycle = require("codediff.ui.lifecycle")

    local file_path = file_data.path
    local old_path = file_data.old_path
    local commit_hash = file_data.commit_hash

    if not file_path or file_path == "" then
      vim.notify("[CodeDiff] No file path for selection", vim.log.levels.WARN)
      return
    end

    if not commit_hash or commit_hash == "" then
      vim.notify("[CodeDiff] No commit hash for selection", vim.log.levels.WARN)
      return
    end

    -- Check if already displaying same file
    local target_hash = base_revision or (commit_hash .. "^")
    local session = lifecycle.get_session(tabpage)
    if not opts.force and session and session.original_revision == target_hash and session.modified_revision == commit_hash then
      if session.modified_path == file_path or session.original_path == file_path then
        return
      end
    end

    vim.schedule(function()
      -- Handle added/deleted files: show single file instead of empty diff
      local file_status = file_data.status
      if file_status == "A" or file_status == "D" then
        local sess = lifecycle.get_session(tabpage)
        local is_inline = sess and sess.layout == "inline"

        if is_inline then
          local rev = file_status == "A" and commit_hash or target_hash
          local path = file_status == "D" and (old_path or file_path) or file_path
          require("codediff.ui.view.inline_view").show_single_file(tabpage, path, {
            revision = rev,
            git_root = git_root,
            rel_path = path,
            side = file_status == "D" and "original" or "modified",
          })
        else
          if file_status == "A" then
            require("codediff.ui.view.side_by_side").show_added_virtual_file(tabpage, git_root, file_path, commit_hash)
          else
            require("codediff.ui.view.side_by_side").show_deleted_virtual_file(tabpage, git_root, old_path or file_path, target_hash)
          end
        end
        return
      end

      ---@type SessionConfig
      local session_config = {
        mode = "history",
        git_root = git_root,
        original_path = base_revision and file_path or (old_path or file_path),
        modified_path = file_path,
        original_revision = target_hash,
        modified_revision = commit_hash,
        line_range = line_range,
      }
      view.update(tabpage, session_config, config.options.diff.jump_to_first_change)
    end)
  end

  history.on_file_select = function(file_data, opts)
    history.current_commit = file_data.commit_hash
    history.current_file = file_data.path
    history.current_selection = vim.deepcopy(file_data)
    selected_commit = file_data.commit_hash
    selected_file = file_data.path
    tree:render()
    on_file_select(file_data, opts)
  end

  -- Store load_commit_files for refresh to re-expand commits
  history._load_commit_files = load_commit_files

  -- Setup keymaps
  keymaps_module.setup(history, {
    is_single_file_mode = is_single_file_mode,
    file_path = opts.file_path,
    git_root = git_root,
    load_commit_files = load_commit_files,
    navigate_next = M.navigate_next,
    navigate_prev = M.navigate_prev,
    nodes_module = nodes_module,
  })

  -- Auto-expand first commit and select first file
  if first_commit_node then
    vim.schedule(function()
      if is_single_file_mode then
        -- Single file mode: directly select the file at first commit
        -- Use file_path from commit data if available (handles renames), fallback to opts.file_path
        local file_path = first_commit_node.data.file_path or opts.file_path
        local file_data = {
          path = file_path,
          commit_hash = first_commit_node.data.hash,
          git_root = git_root,
        }
        history.on_file_select(file_data)
      else
        -- Multi-file mode: expand first commit and select first file
        load_commit_files(first_commit_node, function()
          if first_commit_node:has_children() then
            -- Find first file node (may need to traverse directories in tree mode)
            local function find_first_file(node_ids)
              for _, node_id in ipairs(node_ids) do
                local node = tree:get_node(node_id)
                if node and node.data then
                  if node.data.type == "file" then
                    return node
                  elseif node.data.type == "directory" then
                    -- Expand directory and search its children
                    node:expand()
                    local child_file = find_first_file(node:get_child_ids() or {})
                    if child_file then
                      return child_file
                    end
                  end
                end
              end
              return nil
            end

            local first_file = find_first_file(first_commit_node:get_child_ids() or {})
            if first_file and first_file.data then
              tree:render()
              history.on_file_select(first_file.data)
            end
          end
        end)
      end
    end)
  end

  -- Setup auto-refresh (git watcher + BufEnter)
  local refresh_module = require("codediff.ui.history.refresh")
  refresh_module.setup_auto_refresh(history, tabpage)

  -- Re-render on window resize
  vim.api.nvim_create_autocmd("WinResized", {
    callback = function()
      local resized_wins = vim.v.event.windows or {}
      for _, win in ipairs(resized_wins) do
        if win == history.winid and vim.api.nvim_win_is_valid(win) then
          history.tree:render()
          break
        end
      end
    end,
  })

  return history
end

function M.rerender_current(history)
  if not history then
    return false
  end

  if history.current_selection then
    history.on_file_select(vim.deepcopy(history.current_selection), { force = true })
    return true
  end

  return false
end

local function review_key(commit_hash, file_path)
  if not commit_hash or not file_path then
    return nil
  end
  return commit_hash .. ":" .. file_path
end

local function is_reviewed(history, item)
  local data = item and item.data
  local key = data and review_key(data.commit_hash or data.hash, data.path or data.file_path or history.opts.file_path)
  return key and history.viewed_files and history.viewed_files[key]
end

local function has_unreviewed(history, items)
  for _, item in ipairs(items) do
    if not is_reviewed(history, item) then
      return true
    end
  end
  return false
end

local function notify_all_reviewed()
  vim.notify("All files have been reviewed", vim.log.levels.INFO)
end

local function notify_no_other_unreviewed()
  vim.notify("No other unreviewed files", vim.log.levels.INFO)
end

local function set_history_cursor(history, node)
  local current_win = vim.api.nvim_get_current_win()
  if history.winid and vim.api.nvim_win_is_valid(history.winid) then
    vim.api.nvim_set_current_win(history.winid)
    vim.api.nvim_win_set_cursor(history.winid, { node._line or 1, 0 })
    vim.api.nvim_set_current_win(current_win)
  end
end

local function select_history_file(history, item)
  set_history_cursor(history, item.node)
  history.on_file_select(item.data)
end

-- Get all file nodes from tree (for navigation)
function M.get_all_files(tree)
  local files = {}

  local function collect_files(parent_node)
    if not parent_node:has_children() or not parent_node:is_expanded() then
      return
    end

    for _, child_id in ipairs(parent_node:get_child_ids()) do
      local node = tree:get_node(child_id)
      if node and node.data then
        if node.data.type == "file" then
          table.insert(files, {
            node = node,
            data = node.data,
          })
        elseif node.data.type == "directory" then
          collect_files(node)
        end
      end
    end
  end

  local nodes = tree:get_nodes()
  for _, commit_node in ipairs(nodes) do
    collect_files(commit_node)
  end

  return files
end

-- Navigate to next file
function M.navigate_next(history)
  local all_files = M.get_all_files(history.tree)
  if #all_files == 0 then
    vim.notify("No files in history", vim.log.levels.WARN)
    return
  end

  if not has_unreviewed(history, all_files) then
    notify_all_reviewed()
    return
  end

  local current_commit = history.current_commit
  local current_file = history.current_file

  if not current_commit or not current_file then
    for _, file in ipairs(all_files) do
      if not is_reviewed(history, file) then
        select_history_file(history, file)
        return
      end
    end
  end

  -- Find current index
  local current_index = 0
  for i, file in ipairs(all_files) do
    if file.data.commit_hash == current_commit and file.data.path == current_file then
      current_index = i
      break
    end
  end

  if current_index == 0 then
    for _, file in ipairs(all_files) do
      if not is_reviewed(history, file) then
        select_history_file(history, file)
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
    if file and not is_reviewed(history, file) then
      vim.api.nvim_echo({}, false, {})
      select_history_file(history, file)
      return
    end
  end

  if cycle then
    notify_no_other_unreviewed()
  else
    vim.api.nvim_echo({ { "Last unreviewed file", "WarningMsg" } }, false, {})
  end
end

-- Navigate to previous file
function M.navigate_prev(history)
  local all_files = M.get_all_files(history.tree)
  if #all_files == 0 then
    vim.notify("No files in history", vim.log.levels.WARN)
    return
  end

  if not has_unreviewed(history, all_files) then
    notify_all_reviewed()
    return
  end

  local current_commit = history.current_commit
  local current_file = history.current_file

  if not current_commit or not current_file then
    for i = #all_files, 1, -1 do
      local file = all_files[i]
      if not is_reviewed(history, file) then
        select_history_file(history, file)
        return
      end
    end
  end

  local current_index = 0
  for i, file in ipairs(all_files) do
    if file.data.commit_hash == current_commit and file.data.path == current_file then
      current_index = i
      break
    end
  end

  if current_index == 0 then
    for i = #all_files, 1, -1 do
      local file = all_files[i]
      if not is_reviewed(history, file) then
        select_history_file(history, file)
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
    if file and not is_reviewed(history, file) then
      vim.api.nvim_echo({}, false, {})
      select_history_file(history, file)
      return
    end
  end

  if cycle then
    notify_no_other_unreviewed()
  else
    vim.api.nvim_echo({ { "First unreviewed file", "WarningMsg" } }, false, {})
  end
end

-- Get all commit nodes from tree (for navigation in single-file mode)
function M.get_all_commits(tree)
  local commits = {}
  local nodes = tree:get_nodes()
  for _, node in ipairs(nodes) do
    if node.data and node.data.type == "commit" then
      table.insert(commits, {
        node = node,
        data = node.data,
      })
    end
  end
  return commits
end

local function select_commit(history, commit)
  set_history_cursor(history, commit.node)
  local file_path = commit.data.file_path or history.opts.file_path
  history.on_file_select({
    path = file_path,
    commit_hash = commit.data.hash,
    git_root = history.git_root,
  })
end

-- Navigate to next commit (single-file history mode)
function M.navigate_next_commit(history)
  local all_commits = M.get_all_commits(history.tree)
  if #all_commits == 0 then
    vim.notify("No commits in history", vim.log.levels.WARN)
    return
  end

  if not has_unreviewed(history, all_commits) then
    notify_all_reviewed()
    return
  end

  local current_commit = history.current_commit

  if not current_commit then
    for _, commit in ipairs(all_commits) do
      if not is_reviewed(history, commit) then
        select_commit(history, commit)
        return
      end
    end
  end

  -- Find current index
  local current_index = 0
  for i, commit in ipairs(all_commits) do
    if commit.data.hash == current_commit then
      current_index = i
      break
    end
  end

  if current_index == 0 then
    for _, commit in ipairs(all_commits) do
      if not is_reviewed(history, commit) then
        select_commit(history, commit)
        return
      end
    end
  end

  local cycle = config.options.diff.cycle_next_file
  local search_count = cycle and (#all_commits - 1) or (#all_commits - current_index)
  for offset = 1, search_count do
    local index = current_index + offset
    if cycle then
      index = ((index - 1) % #all_commits) + 1
    end
    local commit = all_commits[index]
    if commit and not is_reviewed(history, commit) then
      vim.api.nvim_echo({}, false, {})
      select_commit(history, commit)
      return
    end
  end

  if cycle then
    notify_no_other_unreviewed()
  else
    vim.api.nvim_echo({ { "Last unreviewed commit", "WarningMsg" } }, false, {})
  end
end

-- Navigate to previous commit (single-file history mode)
function M.navigate_prev_commit(history)
  local all_commits = M.get_all_commits(history.tree)
  if #all_commits == 0 then
    vim.notify("No commits in history", vim.log.levels.WARN)
    return
  end

  if not has_unreviewed(history, all_commits) then
    notify_all_reviewed()
    return
  end

  local current_commit = history.current_commit

  if not current_commit then
    for i = #all_commits, 1, -1 do
      local commit = all_commits[i]
      if not is_reviewed(history, commit) then
        select_commit(history, commit)
        return
      end
    end
  end

  local current_index = 0
  for i, commit in ipairs(all_commits) do
    if commit.data.hash == current_commit then
      current_index = i
      break
    end
  end

  if current_index == 0 then
    for i = #all_commits, 1, -1 do
      local commit = all_commits[i]
      if not is_reviewed(history, commit) then
        select_commit(history, commit)
        return
      end
    end
  end

  local cycle = config.options.diff.cycle_next_file
  local search_count = cycle and (#all_commits - 1) or (current_index - 1)
  for offset = 1, search_count do
    local index = current_index - offset
    if cycle then
      index = ((index - 1) % #all_commits) + 1
    end
    local commit = all_commits[index]
    if commit and not is_reviewed(history, commit) then
      vim.api.nvim_echo({}, false, {})
      select_commit(history, commit)
      return
    end
  end

  if cycle then
    notify_no_other_unreviewed()
  else
    vim.api.nvim_echo({ { "First unreviewed commit", "WarningMsg" } }, false, {})
  end
end

-- Toggle reviewed state for the file/commit under the history cursor, or the current selected entry from diff buffers.
function M.toggle_viewed(history)
  if not history or not history.tree then
    return
  end

  local commit_hash
  local file_path
  if history.bufnr and vim.api.nvim_get_current_buf() == history.bufnr then
    local node = history.tree:get_node()
    if not node or not node.data then
      return
    end

    if node.data.type == "file" then
      commit_hash = node.data.commit_hash
      file_path = node.data.path
    elseif node.data.type == "commit" and history.is_single_file_mode then
      commit_hash = node.data.hash
      file_path = node.data.file_path or history.opts.file_path
    else
      vim.notify("Mark reviewed is only available for files", vim.log.levels.WARN)
      return
    end
  else
    commit_hash = history.current_commit
    file_path = history.current_file
  end

  local key = review_key(commit_hash, file_path)
  if not key then
    vim.notify("No file selected", vim.log.levels.WARN)
    return
  end

  history.viewed_files = history.viewed_files or {}
  if history.viewed_files[key] then
    history.viewed_files[key] = nil
  else
    history.viewed_files[key] = true
  end
  history.tree:render()
end

-- Toggle visibility
function M.toggle_visibility(history)
  if not history or not history.split then
    return
  end

  local tabpage = vim.api.nvim_get_current_tabpage()

  if history.is_hidden then
    history.split:show()
    history.is_hidden = false
    history.winid = history.split.winid
    vim.schedule(function()
      layout.arrange(tabpage)
    end)
  else
    history.split:hide()
    history.is_hidden = true
    vim.schedule(function()
      layout.arrange(tabpage)
    end)
  end
end

return M
