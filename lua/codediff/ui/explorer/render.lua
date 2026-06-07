-- UI rendering for explorer (create split, tree, keymaps)
local M = {}

local Tree = require("codediff.ui.lib.tree")
local Split = require("codediff.ui.lib.split")
local config = require("codediff.config")
local nodes_module = require("codediff.ui.explorer.nodes")
local tree_module = require("codediff.ui.explorer.tree")
local keymaps_module = require("codediff.ui.explorer.keymaps")
local refresh_module = require("codediff.ui.explorer.refresh")
local welcome = require("codediff.ui.welcome")

local function should_show_welcome(explorer)
  if not explorer or not explorer.git_root or explorer.dir1 or explorer.dir2 then
    return false
  end

  local status = explorer.status_result or {}
  local total_files = #(status.unstaged or {}) + #(status.staged or {}) + #(status.conflicts or {})
  return total_files == 0
end

local function show_welcome_page(explorer)
  local lifecycle = require("codediff.ui.lifecycle")
  local session = lifecycle.get_session(explorer.tabpage)
  if not session then
    return false
  end

  local mod_win = session.modified_win
  if not mod_win or not vim.api.nvim_win_is_valid(mod_win) then
    return false
  end

  if session.layout == "inline" then
    local welcome_buf = welcome.create_buffer(vim.api.nvim_win_get_width(mod_win), vim.api.nvim_win_get_height(mod_win))
    require("codediff.ui.view.inline_view").show_welcome(explorer.tabpage, welcome_buf)
    return true
  end

  local orig_win = session.original_win
  local width = vim.api.nvim_win_get_width(mod_win)
  local height = vim.api.nvim_win_get_height(mod_win)
  if orig_win and vim.api.nvim_win_is_valid(orig_win) then
    width = vim.api.nvim_win_get_width(orig_win) + width + 1
    height = vim.api.nvim_win_get_height(orig_win)
  end

  local welcome_buf = welcome.create_buffer(width, height)
  require("codediff.ui.view.side_by_side").show_welcome(explorer.tabpage, welcome_buf)
  return true
end

function M.create(status_result, git_root, tabpage, width, base_revision, target_revision, opts)
  opts = opts or {}
  local is_dir_mode = not git_root -- nil git_root signals directory comparison mode

  -- Get explorer position and size from config
  local explorer_config = config.options.explorer or {}
  local position = explorer_config.position or "left"
  local size
  local text_width -- Width for text rendering (always horizontal width)

  if position == "bottom" then
    size = explorer_config.height or 15
    -- For bottom position, use full window width for text
    text_width = vim.o.columns
  else
    -- Use provided width or config width or default to 40 columns
    size = width or explorer_config.width or 40
    text_width = size
  end

  -- Create split window for explorer
  local split = Split({
    relative = "editor",
    position = position,
    size = size,
    buf_options = {
      modifiable = false,
      readonly = true,
      filetype = "codediff-explorer",
    },
    win_options = {
      number = false,
      relativenumber = false,
      cursorline = true,
      wrap = false,
      signcolumn = "no",
      foldcolumn = "0",
      spell = false,
      winfixwidth = true,
      winfixheight = true,
    },
  })

  -- Mount split first to get bufnr
  split:mount()
  pcall(vim.api.nvim_buf_set_name, split.bufnr, "CodeDiff Explorer [" .. tabpage .. "]")

  -- Honor the initial-visibility config: hide the split immediately if requested.
  -- toggle_explorer (actions.lua) uses split:hide/show to flip this at runtime;
  -- using split:hide() here matches that lifecycle so the user's toggle keymap
  -- continues to work correctly.
  if explorer_config.hidden then
    split:hide()
  end

  -- Track selected path and group for highlighting
  local selected_path = nil
  local selected_group = nil

  -- Create tree with buffer number
  local tree_data = tree_module.create_tree_data(status_result, git_root, base_revision, is_dir_mode, explorer_config.visible_groups)
  local tree = Tree({
    bufnr = split.bufnr,
    nodes = tree_data,
    prepare_node = function(node)
      -- Dynamically get current window width for responsive layout
      local current_width = text_width
      if split.winid and vim.api.nvim_win_is_valid(split.winid) then
        current_width = vim.api.nvim_win_get_width(split.winid)
      end
      return nodes_module.prepare_node(node, current_width, selected_path, selected_group)
    end,
  })

  -- Expand all groups by default before first render
  -- In tree mode, also expand all directories
  local function expand_nodes_recursive(nodes)
    for _, node in ipairs(nodes) do
      if node.data and (node.data.type == "group" or node.data.type == "directory") then
        node:expand()
        if node:has_children() then
          expand_nodes_recursive(node:get_child_ids())
        end
      end
    end
  end

  -- get_child_ids returns IDs, need to get actual nodes
  for _, node in ipairs(tree_data) do
    if node.data and node.data.type == "group" then
      node:expand()
    end
  end

  -- For tree mode, expand directories after initial render when we have node IDs
  local explorer_config = config.options.explorer or {}
  if explorer_config.view_mode == "tree" then
    -- We need to expand directory nodes - they're children of group nodes
    local function expand_all_dirs(parent_node)
      if not parent_node:has_children() then
        return
      end
      for _, child_id in ipairs(parent_node:get_child_ids()) do
        local child = tree:get_node(child_id)
        if child and child.data and child.data.type == "directory" then
          child:expand()
          expand_all_dirs(child)
        end
      end
    end
    for _, node in ipairs(tree_data) do
      expand_all_dirs(node)
    end
  end

  -- Render tree
  tree:render()

  -- Create explorer object early so we can reference it in keymaps
  local explorer = {
    split = split,
    tree = tree,
    bufnr = split.bufnr,
    winid = split.winid,
    git_root = git_root,
    tabpage = tabpage,
    dir1 = opts.dir1,
    dir2 = opts.dir2,
    base_revision = base_revision,
    target_revision = target_revision,
    status_result = status_result, -- Store initial status result
    on_file_select = nil, -- Will be set below
    current_file_path = nil, -- Track currently selected file
    current_file_group = nil, -- Track currently selected file's group (staged/unstaged)
    current_selection = nil, -- Full file selection used to replay current state
    is_hidden = explorer_config.hidden, -- Track visibility state
    visible_groups = vim.deepcopy(explorer_config.visible_groups or { staged = true, unstaged = true, conflicts = true }),
  }

  -- File selection callback - manages its own lifecycle
  local function on_file_select(file_data, opts)
    opts = opts or {}
    local git = require("codediff.core.git")
    local view = require("codediff.ui.view")
    local lifecycle = require("codediff.ui.lifecycle")

    local file_path = file_data.path
    local old_path = file_data.old_path -- For renames: path in original revision
    local group = file_data.group or "unstaged"
    local jump = not opts.no_jump and config.options.diff.jump_to_first_change

    -- Emit CodeDiffFileSelect User autocmd
    vim.api.nvim_exec_autocmds("User", {
      pattern = "CodeDiffFileSelect",
      modeline = false,
      data = {
        tabpage = tabpage,
        path = file_path,
        status = file_data.status,
      },
    })

    -- Dir mode: Compare files from dir1 vs dir2 (no git)
    if is_dir_mode then
      local original_path = explorer.dir1 .. "/" .. file_path
      local modified_path = explorer.dir2 .. "/" .. file_path

      -- Check if already displaying same file
      local session = lifecycle.get_session(tabpage)
      if not opts.force and session and session.original_path == original_path and session.modified_path == modified_path then
        return
      end

      vim.schedule(function()
        ---@type SessionConfig
        local session_config = {
          mode = "explorer",
          git_root = nil,
          original_path = original_path,
          modified_path = modified_path,
          original_revision = nil,
          modified_revision = nil,
        }
        view.update(tabpage, session_config, jump)
      end)
      return
    end

    local abs_path = git_root .. "/" .. file_path

    -- Handle untracked files: show file without diff
    if file_data.status == "??" then
      vim.schedule(function()
        local sess = lifecycle.get_session(tabpage)
        if sess and sess.layout == "inline" then
          require("codediff.ui.view.inline_view").show_single_file(tabpage, abs_path, {
            side = "modified",
          })
        else
          require("codediff.ui.view.side_by_side").show_untracked_file(tabpage, abs_path)
        end
      end)
      return
    end

    -- Handle added files: only one side has the file
    if file_data.status == "A" then
      vim.schedule(function()
        local sess = lifecycle.get_session(tabpage)
        local is_inline = sess and sess.layout == "inline"

        if base_revision and target_revision and target_revision ~= "WORKING" then
          if is_inline then
            require("codediff.ui.view.inline_view").show_single_file(tabpage, file_path, {
              revision = target_revision,
              git_root = git_root,
              rel_path = file_path,
              side = "modified",
            })
          else
            require("codediff.ui.view.side_by_side").show_added_virtual_file(tabpage, git_root, file_path, target_revision)
          end
        elseif group == "staged" then
          if is_inline then
            require("codediff.ui.view.inline_view").show_single_file(tabpage, file_path, {
              revision = ":0",
              git_root = git_root,
              rel_path = file_path,
              side = "modified",
            })
          else
            require("codediff.ui.view.side_by_side").show_added_virtual_file(tabpage, git_root, file_path, ":0")
          end
        else
          if is_inline then
            require("codediff.ui.view.inline_view").show_single_file(tabpage, abs_path, {
              side = "modified",
            })
          else
            require("codediff.ui.view.side_by_side").show_untracked_file(tabpage, abs_path)
          end
        end
      end)
      return
    end

    -- Handle deleted files: show old content without diff
    if file_data.status == "D" then
      vim.schedule(function()
        local sess = lifecycle.get_session(tabpage)
        local is_inline = sess and sess.layout == "inline"

        -- Whenever the explorer is anchored to a base_revision (single-rev
        -- like `:CodeDiff HEAD~5` OR revision-revision like `:CodeDiff A B`),
        -- the deleted file's content lives at base_revision; reading from
        -- HEAD/:0 yields nothing because the file is already gone there.
        -- The HEAD/:0 branch is only correct for plain explorer mode
        -- (no base_revision). Fixes #390.
        if base_revision then
          if is_inline then
            require("codediff.ui.view.inline_view").show_single_file(tabpage, file_path, {
              revision = base_revision,
              git_root = git_root,
              rel_path = file_path,
              side = "original",
            })
          else
            require("codediff.ui.view.side_by_side").show_deleted_virtual_file(tabpage, git_root, file_path, base_revision)
          end
        else
          if is_inline then
            local revision = (group == "staged") and "HEAD" or ":0"
            require("codediff.ui.view.inline_view").show_single_file(tabpage, file_path, {
              revision = revision,
              git_root = git_root,
              rel_path = file_path,
              side = "original",
            })
          else
            require("codediff.ui.view.side_by_side").show_deleted_file(tabpage, git_root, file_path, abs_path, group)
          end
        end
      end)
      return
    end

    -- Check if this exact diff is already being displayed
    -- Same file can have different diffs (staged vs HEAD, working vs staged)
    local session = lifecycle.get_session(tabpage)
    if session then
      local is_same_file = (session.modified_path == abs_path or session.modified_path == file_path or (session.git_root and session.original_path == file_path))

      if is_same_file and not opts.force then
        -- Conflict mode: skip if already showing the same conflict file
        -- (revisions :2/:3 are mutable so the staged-base-change logic below
        --  would incorrectly force a re-render on every refresh cycle)
        if group == "conflicts" and session.result_win and vim.api.nvim_win_is_valid(session.result_win) then
          return
        end

        -- Check if it's the same diff comparison
        local is_staged_diff = group == "staged"
        local current_is_staged = session.modified_revision == ":0"

        if is_staged_diff == current_is_staged then
          -- Same diff type — but also check if comparison base changed
          -- (e.g. unstaged file gains staged changes: HEAD → :0)
          if group ~= "staged" then
            local current_status = explorer.status_result
            if current_status then
              local file_has_staged = false
              for _, sf in ipairs(current_status.staged or {}) do
                if sf.path == file_path then
                  file_has_staged = true
                  break
                end
              end
              local current_is_mutable = session.original_revision and session.original_revision:match("^:[0-3]$")
              if file_has_staged ~= (current_is_mutable and true or false) then
                -- Comparison base needs to change — don't skip
              else
                return
              end
            else
              return
            end
          else
            return
          end
        end
      end
    end

    if base_revision and target_revision and target_revision ~= "WORKING" then
      -- Two revision mode: Compare base vs target
      vim.schedule(function()
        ---@type SessionConfig
        local session_config = {
          mode = "explorer",
          git_root = git_root,
          original_path = old_path or file_path,
          modified_path = file_path,
          original_revision = base_revision,
          modified_revision = target_revision,
        }
        view.update(tabpage, session_config, jump)
      end)
      return
    end

    -- Use base_revision if provided, otherwise default to HEAD
    local target_revision_single = base_revision or "HEAD"
    git.resolve_revision(target_revision_single, git_root, function(err_resolve, commit_hash)
      if err_resolve then
        vim.schedule(function()
          vim.notify(err_resolve, vim.log.levels.ERROR)
        end)
        return
      end

      if base_revision then
        -- Revision mode: Simple comparison of working tree vs base_revision
        vim.schedule(function()
          ---@type SessionConfig
          local session_config = {
            mode = "explorer",
            git_root = git_root,
            original_path = old_path or file_path,
            modified_path = abs_path,
            original_revision = commit_hash,
            modified_revision = nil,
          }
          view.update(tabpage, session_config, jump)
        end)
      elseif group == "conflicts" then
        -- Merge conflict: Show incoming (:3) vs current (:2), both diffed against base (:1)
        -- Position controlled by config.diff.conflict_ours_position (absolute screen position)
        vim.schedule(function()
          -- Determine conflict buffer positions based on config
          -- conflict_ours_position controls where :2 (OURS) appears on screen
          local ours_position = config.options.diff.conflict_ours_position or "right"

          -- After conflict_window.lua's win_splitmove(rightbelow=false):
          -- - original_win is on LEFT
          -- - modified_win is on RIGHT
          local original_rev, modified_rev
          if ours_position == "right" then
            original_rev = ":3" -- THEIRS in original_win (LEFT)
            modified_rev = ":2" -- OURS in modified_win (RIGHT)
          else
            original_rev = ":2" -- OURS in original_win (LEFT)
            modified_rev = ":3" -- THEIRS in modified_win (RIGHT)
          end

          ---@type SessionConfig
          local session_config = {
            mode = "explorer",
            git_root = git_root,
            original_path = file_path,
            modified_path = file_path,
            original_revision = original_rev,
            modified_revision = modified_rev,
            conflict = true,
          }
          view.update(tabpage, session_config, jump)
        end)
      elseif group == "staged" then
        -- Staged changes: Compare staged (:0) vs HEAD (both virtual)
        -- For renames: old_path in HEAD, new path in staging
        -- No pre-fetching needed, virtual files will load via BufReadCmd
        vim.schedule(function()
          ---@type SessionConfig
          local session_config = {
            mode = "explorer",
            git_root = git_root,
            original_path = old_path or file_path, -- Use old_path if rename
            modified_path = file_path, -- New path after rename
            original_revision = commit_hash,
            modified_revision = ":0",
          }
          view.update(tabpage, session_config, jump)
        end)
      else
        -- Unstaged changes: Compare working tree vs staged (if exists) or HEAD
        -- Check if file is in staged list
        local is_staged = false
        -- Use current status_result from explorer object
        local current_status = explorer.status_result or status_result
        for _, staged_file in ipairs(current_status.staged) do
          if staged_file.path == file_path then
            is_staged = true
            break
          end
        end

        local original_revision = is_staged and ":0" or commit_hash

        -- No pre-fetching needed, buffers will load content
        vim.schedule(function()
          ---@type SessionConfig
          local session_config = {
            mode = "explorer",
            git_root = git_root,
            original_path = file_path,
            modified_path = abs_path,
            original_revision = original_revision,
            modified_revision = nil,
          }
          view.update(tabpage, session_config, jump)
        end)
      end
    end)
  end

  -- Wrap on_file_select to track current file and group
  explorer.on_file_select = function(file_data, opts)
    explorer.current_file_path = file_data.path
    explorer.current_file_group = file_data.group
    explorer.current_selection = vim.deepcopy(file_data)
    selected_path = file_data.path
    selected_group = file_data.group
    tree:render()
    on_file_select(file_data, opts)
  end

  -- Clear selection highlight (used when showing welcome page)
  explorer.clear_selection = function()
    selected_path = nil
    selected_group = nil
    tree:render()
  end

  -- Setup keymaps (delegated to keymaps module)
  keymaps_module.setup(explorer)

  -- Auto-open diff for the node under cursor after j/k (or arrow keys).
  -- Hooks j/k/<Down>/<Up> instead of CursorMoved so mouse clicks, :N jumps,
  -- and scrolls don't trigger an open. Buffer-local keymaps die with the
  -- buffer, so no manual cleanup needed.
  if explorer_config.auto_open_on_cursor then
    local function open_under_cursor()
      if not vim.api.nvim_buf_is_valid(split.bufnr) then
        return
      end
      local node = tree:get_node()
      if not node or not node.data then
        return
      end
      local node_type = node.data.type
      if node_type == "group" or node_type == "directory" then
        return
      end
      if explorer.current_file_path == node.data.path
          and explorer.current_file_group == node.data.group then
        return
      end
      explorer.on_file_select(node.data)
    end
    for _, key in ipairs({ "j", "k", "<Down>", "<Up>" }) do
      vim.keymap.set("n", key, function()
        local motion = key == "<Down>" and "j" or key == "<Up>" and "k" or key
        vim.cmd("normal! " .. motion)
        open_under_cursor()
      end, { buffer = split.bufnr, silent = true, desc = "codediff: move and auto-open file" })
    end
  end

  -- Find a file in the status lists, returns (file, group) or (nil, nil)
  local function find_file_in_status(path)
    if status_result.conflicts then
      for _, f in ipairs(status_result.conflicts) do
        if f.path == path then
          return f, "conflicts"
        end
      end
    end
    for _, f in ipairs(status_result.unstaged) do
      if f.path == path then
        return f, "unstaged"
      end
    end
    for _, f in ipairs(status_result.staged) do
      if f.path == path then
        return f, "staged"
      end
    end
    return nil, nil
  end

  -- Select initial file: prefer focus_file (current buffer) if changed, else first file
  local initial_file, initial_file_group
  local focus_file = opts and opts.focus_file
  if focus_file then
    initial_file, initial_file_group = find_file_in_status(focus_file)
  end
  if not initial_file then
    if status_result.conflicts and #status_result.conflicts > 0 then
      initial_file, initial_file_group = status_result.conflicts[1], "conflicts"
    elseif #status_result.unstaged > 0 then
      initial_file, initial_file_group = status_result.unstaged[1], "unstaged"
    elseif #status_result.staged > 0 then
      initial_file, initial_file_group = status_result.staged[1], "staged"
    end
  end

  if initial_file then
    vim.schedule(function()
      -- Scroll explorer to the selected file using tree:get_node(line) lookup
      if explorer.winid and vim.api.nvim_win_is_valid(explorer.winid) and vim.api.nvim_buf_is_valid(explorer.bufnr) then
        local line_count = vim.api.nvim_buf_line_count(explorer.bufnr)
        for line = 1, line_count do
          local node = explorer.tree:get_node(line)
          if node and node.data and node.data.path == initial_file.path and node.data.group == initial_file_group then
            vim.api.nvim_win_set_cursor(explorer.winid, { line, 0 })
            break
          end
        end
      end

      explorer.on_file_select({
        path = initial_file.path,
        old_path = initial_file.old_path,
        status = initial_file.status,
        git_root = git_root,
        group = initial_file_group,
      })
    end)
  end

  -- Setup auto-refresh
  refresh_module.setup_auto_refresh(explorer, tabpage)

  -- Re-render on window resize for dynamic width
  vim.api.nvim_create_autocmd("WinResized", {
    callback = function()
      -- Check if explorer window was resized
      local resized_wins = vim.v.event.windows or {}
      for _, win in ipairs(resized_wins) do
        if win == explorer.winid and vim.api.nvim_win_is_valid(win) then
          explorer.tree:render()
          break
        end
      end
    end,
  })

  return explorer
end

function M.rerender_current(explorer)
  if not explorer then
    return false
  end

  if explorer.current_selection then
    explorer.on_file_select(vim.deepcopy(explorer.current_selection), { force = true })
    return true
  end

  local lifecycle = require("codediff.ui.lifecycle")
  local session = lifecycle.get_session(explorer.tabpage)
  if not session then
    return false
  end

  if should_show_welcome(explorer) and show_welcome_page(explorer) then
    return true
  end

  return false
end

M.show_welcome_page = show_welcome_page

-- Setup auto-refresh on file save and focus

return M
