-- Side-by-side diff view engine
-- Handles creation and updating of two-window diff views
local M = {}

local lifecycle = require("codediff.ui.lifecycle")
local virtual_file = require("codediff.core.virtual_file")
local auto_refresh = require("codediff.ui.auto_refresh")
local config = require("codediff.config")
local core = require("codediff.ui.core")
local path = require("codediff.core.path")

-- Eagerly load explorer and history to avoid lazy require failures
-- when CWD changes in vim.schedule callbacks
local explorer_module = require("codediff.ui.explorer")
local history_module = require("codediff.ui.history")
local layout = require("codediff.ui.layout")

local helpers = require("codediff.ui.view.helpers")
local render = require("codediff.ui.view.render")
local view_keymaps = require("codediff.ui.view.keymaps")
local conflict_window = require("codediff.ui.view.conflict_window")
local panel = require("codediff.ui.view.panel")
local welcome_window = require("codediff.ui.view.welcome_window")

local is_virtual_revision = helpers.is_virtual_revision
local prepare_buffer = helpers.prepare_buffer
local compute_and_render = render.compute_and_render
local compute_and_render_conflict = render.compute_and_render_conflict
local setup_auto_refresh = render.setup_auto_refresh
local setup_conflict_result_window = conflict_window.setup_conflict_result_window
local setup_all_keymaps = view_keymaps.setup_all_keymaps

-- ============================================================================
-- Create
-- ============================================================================

---@param session_config SessionConfig
---@param filetype? string
---@param on_ready? function
---@return table|nil
function M.create(session_config, filetype, on_ready)
  -- Create new tab
  vim.cmd("tabnew")

  local tabpage = vim.api.nvim_get_current_tabpage()

  -- For explorer mode with empty paths OR dir mode (git_root == nil with explorer_data),
  -- or history mode, create empty panes and skip buffer setup
  local is_explorer_placeholder = session_config.mode == "explorer" and (path.is_empty(session_config.original) or (not session_config.git_root and session_config.explorer_data))

  local is_history_placeholder = session_config.mode == "history" and session_config.history_data

  local original_win, modified_win, original_info, modified_info, initial_buf

  -- Split command: Use explicit positioning to ignore user's splitright setting
  -- "rightbelow vsplit" puts new window on RIGHT, "leftabove vsplit" puts it on LEFT
  -- We want modified (new) on RIGHT when original_position == "left"
  local split_cmd = config.options.diff.original_position == "right" and "leftabove vsplit" or "rightbelow vsplit"

  if is_explorer_placeholder or is_history_placeholder then
    -- Explorer/History mode: Create empty split panes, skip buffer loading
    -- Panel will populate via first file selection
    initial_buf = vim.api.nvim_get_current_buf()
    original_win = vim.api.nvim_get_current_win()
    vim.cmd(split_cmd)
    modified_win = vim.api.nvim_get_current_win()

    -- Create separate scratch buffers for each window (so initial_buf can be deleted)
    local orig_scratch = vim.api.nvim_create_buf(false, true)
    local mod_scratch = vim.api.nvim_create_buf(false, true)
    vim.bo[orig_scratch].buftype = "nofile"
    vim.bo[mod_scratch].buftype = "nofile"
    pcall(vim.api.nvim_buf_set_name, orig_scratch, "CodeDiff " .. tabpage .. ".1")
    pcall(vim.api.nvim_buf_set_name, mod_scratch, "CodeDiff " .. tabpage .. ".2")
    vim.api.nvim_win_set_buf(original_win, orig_scratch)
    vim.api.nvim_win_set_buf(modified_win, mod_scratch)
    welcome_window.sync(original_win)
    welcome_window.sync(modified_win)

    -- Create placeholder buffer info (will be updated by explorer)
    original_info = { bufnr = orig_scratch }
    modified_info = { bufnr = mod_scratch }
  else
    -- Normal mode: Full buffer setup
    local original_is_virtual = is_virtual_revision(session_config.original_revision)
    local modified_is_virtual = is_virtual_revision(session_config.modified_revision)

    original_info = prepare_buffer(original_is_virtual, session_config.git_root, session_config.original_revision, session_config.original)
    modified_info = prepare_buffer(modified_is_virtual, session_config.git_root, session_config.modified_revision, session_config.modified)

    initial_buf = vim.api.nvim_get_current_buf()
    original_win = vim.api.nvim_get_current_win()

    -- Load original buffer
    if original_info.needs_edit then
      local cmd = original_is_virtual and "edit! " or "edit "
      vim.cmd(cmd .. vim.fn.fnameescape(original_info.target))
      original_info.bufnr = vim.api.nvim_get_current_buf()
    else
      vim.api.nvim_win_set_buf(original_win, original_info.bufnr)
    end

    vim.cmd(split_cmd)
    modified_win = vim.api.nvim_get_current_win()

    -- Load modified buffer
    if modified_info.needs_edit then
      local cmd = modified_is_virtual and "edit! " or "edit "
      vim.cmd(cmd .. vim.fn.fnameescape(modified_info.target))
      modified_info.bufnr = vim.api.nvim_get_current_buf()
    else
      vim.api.nvim_win_set_buf(modified_win, modified_info.bufnr)
    end
    welcome_window.sync(original_win)
    welcome_window.sync(modified_win)
  end

  -- Clean up initial buffer
  if vim.api.nvim_buf_is_valid(initial_buf) and initial_buf ~= original_info.bufnr and initial_buf ~= modified_info.bufnr then
    pcall(vim.api.nvim_buf_delete, initial_buf, { force = true })
  end

  -- Window options (scrollbind will be set by compute_and_render)
  -- Note: number and relativenumber are intentionally NOT set to honor user's local config
  local win_opts = {
    cursorline = true,
    wrap = false,
    list = false,
  }

  for opt, val in pairs(win_opts) do
    vim.wo[original_win][opt] = val
    vim.wo[modified_win][opt] = val
  end

  -- For explorer placeholder, create minimal session without rendering
  if is_explorer_placeholder or is_history_placeholder then
    -- Create minimal lifecycle session for explorer/history (update will populate it)
    lifecycle.create_session(
      tabpage,
      session_config.mode,
      session_config.git_root,
      "", -- Empty paths indicate placeholder
      "",
      nil,
      nil,
      original_info.bufnr,
      modified_info.bufnr,
      original_win,
      modified_win,
      {}, -- Empty diff result - will be updated on first file selection
      function()
        local ob, mb = lifecycle.get_buffers(tabpage)
        if not ob or not mb then
          return
        end
        local is_explorer = lifecycle.get_mode(tabpage) == "explorer"
        setup_all_keymaps(tabpage, ob, mb, is_explorer)
      end,
      session_config.exit_on_close
    )
  else
    -- Normal mode: Full rendering
    local original_is_virtual = is_virtual_revision(session_config.original_revision)
    local modified_is_virtual = is_virtual_revision(session_config.modified_revision)

    -- Set up rendering after buffers are ready
    local render_everything = function()
      -- Guard: Check if windows are still valid (they may have been closed during async wait)
      if not vim.api.nvim_win_is_valid(original_win) or not vim.api.nvim_win_is_valid(modified_win) then
        return
      end

      -- Guard: Check if buffers are still valid
      if not vim.api.nvim_buf_is_valid(original_info.bufnr) or not vim.api.nvim_buf_is_valid(modified_info.bufnr) then
        return
      end

      -- Ensure correct tab context — when called from vim.schedule in a batch
      -- loop, the current tab may differ. Commands like syncbind operate on the
      -- current tab, so we must switch to the target tab first.
      local target_tab = vim.api.nvim_win_get_tabpage(modified_win)
      local cur_tab = vim.api.nvim_get_current_tabpage()
      if cur_tab ~= target_tab then
        vim.api.nvim_set_current_tabpage(target_tab)
      end

      -- Always read from buffers (single source of truth)
      local original_lines = vim.api.nvim_buf_get_lines(original_info.bufnr, 0, -1, false)
      local modified_lines = vim.api.nvim_buf_get_lines(modified_info.bufnr, 0, -1, false)

      if session_config.conflict then
        -- Conflict mode: Fetch base content and render both sides against base
        local git = require("codediff.core.git")
        local base_revision = ":1"

        git.get_file_content(base_revision, session_config.git_root, session_config.original.relative, function(err, base_lines)
          -- For add/add conflicts (AA), there's no base version - use empty base
          if err then
            base_lines = {}
          end

          vim.schedule(function()
            local conflict_diffs = compute_and_render_conflict(
              original_info.bufnr,
              modified_info.bufnr,
              base_lines,
              original_lines,
              modified_lines,
              original_win,
              modified_win,
              config.options.diff.jump_to_first_change
            )

            if conflict_diffs then
              -- Create lifecycle session for conflict mode
              lifecycle.create_session(
                tabpage,
                session_config.mode,
                session_config.git_root,
                session_config.original,
                session_config.modified,
                session_config.original_revision,
                session_config.modified_revision,
                original_info.bufnr,
                modified_info.bufnr,
                original_win,
                modified_win,
                conflict_diffs.base_to_modified_diff,
                function()
                  local ob, mb = lifecycle.get_buffers(tabpage)
                  if not ob or not mb then
                    return
                  end
                  setup_all_keymaps(tabpage, ob, mb, false)
                  local conflict = require("codediff.ui.conflict")
                  conflict.setup_keymaps(tabpage)
                end,
                session_config.exit_on_close
              )

              -- Setup result window and keymaps
              local success = setup_conflict_result_window(tabpage, session_config, original_win, modified_win, base_lines, conflict_diffs, false)
              if success then
                setup_all_keymaps(tabpage, original_info.bufnr, modified_info.bufnr, false)
                -- Setup conflict keymaps AFTER setup_all_keymaps to override do/dp
                local conflict = require("codediff.ui.conflict")
                conflict.setup_keymaps(tabpage)
              end

              -- Signal that view is ready
              if on_ready then
                on_ready()
              end
            end
          end)
        end)
      else
        -- Normal mode: Compute and render diff between left and right
        local lines_diff = compute_and_render(
          original_info.bufnr,
          modified_info.bufnr,
          original_lines,
          modified_lines,
          original_is_virtual,
          modified_is_virtual,
          original_win,
          modified_win,
          config.options.diff.jump_to_first_change
        )

        if lines_diff then
          -- Create complete lifecycle session (one step!)
          lifecycle.create_session(
            tabpage,
            session_config.mode,
            session_config.git_root,
            session_config.original,
            session_config.modified,
            session_config.original_revision,
            session_config.modified_revision,
            original_info.bufnr,
            modified_info.bufnr,
            original_win,
            modified_win,
            lines_diff,
            function()
              local ob, mb = lifecycle.get_buffers(tabpage)
              if not ob or not mb then
                return
              end
              local is_explorer = lifecycle.get_mode(tabpage) == "explorer"
              setup_all_keymaps(tabpage, ob, mb, is_explorer)
            end,
            session_config.exit_on_close
          )
          -- Enable auto-refresh for real file buffers only
          setup_auto_refresh(original_info.bufnr, modified_info.bufnr, original_is_virtual, modified_is_virtual)

          -- Setup all keymaps in one place (centralized)
          setup_all_keymaps(tabpage, original_info.bufnr, modified_info.bufnr, false)

          -- Setup auto-sync on file switch (after session is complete!)
          lifecycle.setup_auto_sync_on_file_switch(tabpage, original_is_virtual, modified_is_virtual)

          -- Signal that view is ready
          if on_ready then
            on_ready()
          end
        end
      end
    end

    -- Choose timing based on buffer types
    local has_virtual = original_is_virtual or modified_is_virtual

    if has_virtual then
      -- Virtual file(s): Wait for BufReadCmd to load content
      local group = vim.api.nvim_create_augroup("CodeDiffVirtualFileHighlight_" .. tabpage, { clear = true })

      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "CodeDiffVirtualFileLoaded",
        callback = function(event)
          if not event.data or not event.data.buf then
            return
          end
        end,
      })

      -- Re-implementing the simple tracker locally
      local loaded_buffers = {}

      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "CodeDiffVirtualFileLoaded",
        callback = function(event)
          if not event.data or not event.data.buf then
            return
          end
          local loaded_buf = event.data.buf

          if (original_is_virtual and loaded_buf == original_info.bufnr) or (modified_is_virtual and loaded_buf == modified_info.bufnr) then
            loaded_buffers[loaded_buf] = true

            local ready = true
            if original_is_virtual and not loaded_buffers[original_info.bufnr] then
              ready = false
            end
            if modified_is_virtual and not loaded_buffers[modified_info.bufnr] then
              ready = false
            end

            if ready then
              vim.schedule(render_everything)
              vim.api.nvim_del_augroup_by_id(group)
            end
          end
        end,
      })
    else
      -- Real files only: Defer until :edit completes
      vim.schedule(render_everything)
    end
  end

  -- Setup panels (explorer sidebar, history panel)
  panel.setup_explorer(tabpage, session_config, original_win, modified_win)
  panel.setup_history(tabpage, session_config, original_win, modified_win)

  -- Emit CodeDiffOpen User autocmd
  vim.api.nvim_exec_autocmds("User", {
    pattern = "CodeDiffOpen",
    modeline = false,
    data = {
      tabpage = tabpage,
      mode = session_config.mode,
    },
  })

  return {
    original_buf = original_info.bufnr,
    modified_buf = modified_info.bufnr,
    original_win = original_win,
    modified_win = modified_win,
  }
end

-- ============================================================================
-- Update
-- ============================================================================

---@param tabpage number
---@param session_config SessionConfig
---@param auto_scroll_to_first_hunk boolean?
---@return boolean
function M.update(tabpage, session_config, auto_scroll_to_first_hunk)
  -- Save current window to restore focus after update
  local saved_current_win = vim.api.nvim_get_current_win()

  -- Get existing session
  local session = lifecycle.get_session(tabpage)
  if not session then
    return false
  end
  session.single_side = nil

  -- Get existing buffers and windows
  local old_original_buf, old_modified_buf = lifecycle.get_buffers(tabpage)
  local original_win, modified_win = lifecycle.get_windows(tabpage)

  if not old_original_buf or not old_modified_buf then
    return false
  end
  if not original_win and not modified_win then
    return false
  end

  -- Disable auto-refresh temporarily
  auto_refresh.disable(old_original_buf)
  auto_refresh.disable(old_modified_buf)

  -- Clear highlights from old buffers (before they're replaced/deleted)
  lifecycle.clear_highlights(old_original_buf)
  lifecycle.clear_highlights(old_modified_buf)

  -- Clear stored_diff_result to signal that an update is in progress
  lifecycle.update_diff_result(tabpage, nil)

  -- Handle result window when switching between conflict and non-conflict modes
  local old_result_bufnr, old_result_win = lifecycle.get_result(tabpage)
  if not session_config.conflict and old_result_win and vim.api.nvim_win_is_valid(old_result_win) then
    vim.api.nvim_win_close(old_result_win, false)
    lifecycle.set_result(tabpage, nil, nil)
  end

  -- Restore second window if returning from single-pane mode
  if session.single_pane then
    local split_cmd = config.options.diff.original_position == "right" and "leftabove vsplit" or "rightbelow vsplit"

    if not original_win or not vim.api.nvim_win_is_valid(original_win) then
      -- Original was closed (untracked file) — recreate it to the left of modified
      vim.api.nvim_set_current_win(modified_win)
      vim.cmd(config.options.diff.original_position == "right" and "rightbelow vsplit" or "leftabove vsplit")
      original_win = vim.api.nvim_get_current_win()
      vim.w[original_win].codediff_restore = 1
      session.original_win = original_win
    elseif not modified_win or not vim.api.nvim_win_is_valid(modified_win) then
      -- Modified was closed (deleted file) — recreate it to the right of original
      vim.api.nvim_set_current_win(original_win)
      vim.cmd(split_cmd)
      modified_win = vim.api.nvim_get_current_win()
      vim.w[modified_win].codediff_restore = 1
      session.modified_win = modified_win
    end

    -- Clear single_pane AFTER new window has codediff_restore set
    session.single_pane = nil
    layout.arrange(tabpage)
  end

  -- Determine if new buffers are virtual
  local original_is_virtual = is_virtual_revision(session_config.original_revision)
  local modified_is_virtual = is_virtual_revision(session_config.modified_revision)

  -- Prepare new buffer information
  local original_info = prepare_buffer(original_is_virtual, session_config.git_root, session_config.original_revision, session_config.original)
  local modified_info = prepare_buffer(modified_is_virtual, session_config.git_root, session_config.modified_revision, session_config.modified)

  -- Determine if we need to wait for virtual file content
  local wait_state = {
    original = original_is_virtual and original_info.needs_edit,
    modified = modified_is_virtual and modified_info.needs_edit,
  }

  local render_everything = function()
    -- Guard: Check if windows are still valid
    if not vim.api.nvim_win_is_valid(original_win) or not vim.api.nvim_win_is_valid(modified_win) then
      return
    end

    -- Guard: Check if buffers are still valid
    if not vim.api.nvim_buf_is_valid(original_info.bufnr) or not vim.api.nvim_buf_is_valid(modified_info.bufnr) then
      return
    end

    -- Always read from buffers (single source of truth)
    local original_lines = vim.api.nvim_buf_get_lines(original_info.bufnr, 0, -1, false)
    local modified_lines = vim.api.nvim_buf_get_lines(modified_info.bufnr, 0, -1, false)

    local should_auto_scroll = auto_scroll_to_first_hunk == true
    local lines_diff

    if session_config.conflict then
      -- Conflict mode: Fetch base content and render both sides against base
      local git = require("codediff.core.git")
      local base_revision = ":1"

      git.get_file_content(base_revision, session_config.git_root, session_config.original.relative, function(err, base_lines)
        if err then
          base_lines = {}
        end

        vim.schedule(function()
          local conflict_diffs =
            compute_and_render_conflict(original_info.bufnr, modified_info.bufnr, base_lines, original_lines, modified_lines, original_win, modified_win, should_auto_scroll)

          if conflict_diffs then
            lifecycle.update_buffers(tabpage, original_info.bufnr, modified_info.bufnr)
            lifecycle.update_git_root(tabpage, session_config.git_root)
            lifecycle.update_revisions(tabpage, session_config.original_revision, session_config.modified_revision)
            lifecycle.update_diff_result(tabpage, conflict_diffs.base_to_modified_diff)
            lifecycle.update_changedtick(tabpage, vim.api.nvim_buf_get_changedtick(original_info.bufnr), vim.api.nvim_buf_get_changedtick(modified_info.bufnr))
            local is_explorer_mode = session.mode == "explorer"
            local success = setup_conflict_result_window(tabpage, session_config, original_win, modified_win, base_lines, conflict_diffs, true)
            if success then
              setup_all_keymaps(tabpage, original_info.bufnr, modified_info.bufnr, is_explorer_mode)
              local conflict = require("codediff.ui.conflict")
              conflict.setup_keymaps(tabpage)
            end
          end
        end)
      end)
    else
      -- Normal mode: Compute and render diff between left and right
      lines_diff = compute_and_render(
        original_info.bufnr,
        modified_info.bufnr,
        original_lines,
        modified_lines,
        original_is_virtual,
        modified_is_virtual,
        original_win,
        modified_win,
        should_auto_scroll,
        session_config.line_range
      )

      if lines_diff then
        lifecycle.update_buffers(tabpage, original_info.bufnr, modified_info.bufnr)
        lifecycle.update_git_root(tabpage, session_config.git_root)
        lifecycle.update_revisions(tabpage, session_config.original_revision, session_config.modified_revision)
        lifecycle.update_diff_result(tabpage, lines_diff)
        lifecycle.update_changedtick(tabpage, vim.api.nvim_buf_get_changedtick(original_info.bufnr), vim.api.nvim_buf_get_changedtick(modified_info.bufnr))
        setup_auto_refresh(original_info.bufnr, modified_info.bufnr, original_is_virtual, modified_is_virtual)

        local is_explorer_mode = session.mode == "explorer"
        setup_all_keymaps(tabpage, original_info.bufnr, modified_info.bufnr, is_explorer_mode)

        -- Restore focus to the window that was active before update
        if saved_current_win and vim.api.nvim_win_is_valid(saved_current_win) then
          vim.api.nvim_set_current_win(saved_current_win)
        end
      end
    end
  end

  -- Set up autocmd to wait for virtual file loads BEFORE triggering any async operations
  local autocmd_group = nil
  if wait_state.original or wait_state.modified then
    autocmd_group = vim.api.nvim_create_augroup("CodeDiffVirtualFileUpdate_" .. tabpage, { clear = true })

    vim.api.nvim_create_autocmd("User", {
      group = autocmd_group,
      pattern = "CodeDiffVirtualFileLoaded",
      callback = function(event)
        if not event.data or not event.data.buf then
          return
        end

        local loaded_buf = event.data.buf

        if wait_state.original and loaded_buf == original_info.bufnr then
          wait_state.original = false
        end
        if wait_state.modified and loaded_buf == modified_info.bufnr then
          wait_state.modified = false
        end

        if not wait_state.original and not wait_state.modified then
          vim.schedule(render_everything)
          vim.api.nvim_del_augroup_by_id(autocmd_group)
        end
      end,
    })
  end

  -- Load buffers into windows
  if vim.api.nvim_win_is_valid(original_win) then
    if original_info.needs_edit then
      if original_is_virtual then
        if original_info.bufnr and vim.api.nvim_buf_is_valid(original_info.bufnr) then
          vim.api.nvim_win_set_buf(original_win, original_info.bufnr)
          virtual_file.refresh_buffer(original_info.bufnr)
        else
          vim.api.nvim_set_current_win(original_win)
          vim.cmd("edit! " .. vim.fn.fnameescape(original_info.target))
          original_info.bufnr = vim.api.nvim_get_current_buf()
        end
      else
        local bufnr = vim.fn.bufadd(original_info.target)
        vim.fn.bufload(bufnr)
        original_info.bufnr = bufnr
        vim.api.nvim_win_set_buf(original_win, original_info.bufnr)
      end
    else
      if vim.api.nvim_buf_is_valid(original_info.bufnr) then
        vim.api.nvim_win_set_buf(original_win, original_info.bufnr)
        if not original_is_virtual then
          vim.api.nvim_buf_call(original_info.bufnr, function()
            vim.cmd("checktime")
          end)
        end
      else
        if original_is_virtual then
          vim.api.nvim_set_current_win(original_win)
          vim.cmd("edit! " .. vim.fn.fnameescape(original_info.target))
          original_info.bufnr = vim.api.nvim_get_current_buf()
        else
          local bufnr = vim.fn.bufadd(original_info.target)
          vim.fn.bufload(bufnr)
          original_info.bufnr = bufnr
          vim.api.nvim_win_set_buf(original_win, original_info.bufnr)
        end
      end
    end
  end

  if vim.api.nvim_win_is_valid(modified_win) then
    if modified_info.needs_edit then
      if modified_is_virtual then
        if modified_info.bufnr and vim.api.nvim_buf_is_valid(modified_info.bufnr) then
          vim.api.nvim_win_set_buf(modified_win, modified_info.bufnr)
          virtual_file.refresh_buffer(modified_info.bufnr)
        else
          vim.api.nvim_set_current_win(modified_win)
          vim.cmd("edit! " .. vim.fn.fnameescape(modified_info.target))
          modified_info.bufnr = vim.api.nvim_get_current_buf()
        end
      else
        local bufnr = vim.fn.bufadd(modified_info.target)
        vim.fn.bufload(bufnr)
        modified_info.bufnr = bufnr
        vim.api.nvim_win_set_buf(modified_win, modified_info.bufnr)
      end
    else
      if vim.api.nvim_buf_is_valid(modified_info.bufnr) then
        vim.api.nvim_win_set_buf(modified_win, modified_info.bufnr)
        if not modified_is_virtual then
          vim.api.nvim_buf_call(modified_info.bufnr, function()
            vim.cmd("checktime")
          end)
        end
      else
        if modified_is_virtual then
          vim.api.nvim_set_current_win(modified_win)
          vim.cmd("edit! " .. vim.fn.fnameescape(modified_info.target))
          modified_info.bufnr = vim.api.nvim_get_current_buf()
        else
          local bufnr = vim.fn.bufadd(modified_info.target)
          vim.fn.bufload(bufnr)
          modified_info.bufnr = bufnr
          vim.api.nvim_win_set_buf(modified_win, modified_info.bufnr)
        end
      end
    end
  end

  welcome_window.sync(original_win)
  welcome_window.sync(modified_win)

  -- Update lifecycle session metadata
  lifecycle.update_paths(tabpage, session_config.original, session_config.modified)

  -- Delete old virtual buffers if they were virtual AND are not reused
  if lifecycle.is_original_virtual(tabpage) and old_original_buf ~= original_info.bufnr and old_original_buf ~= modified_info.bufnr then
    pcall(vim.api.nvim_buf_delete, old_original_buf, { force = true })
  end

  if lifecycle.is_modified_virtual(tabpage) and old_modified_buf ~= modified_info.bufnr and old_modified_buf ~= original_info.bufnr then
    pcall(vim.api.nvim_buf_delete, old_modified_buf, { force = true })
  end

  -- If no virtual files need loading, render immediately
  if not autocmd_group then
    vim.schedule(render_everything)
  end

  return true
end

-- ============================================================================
-- Single-file display (no diff) for explorer special cases
-- ============================================================================

--- Core implementation for showing a single file without diff.
--- Closes the empty pane and loads the file into the remaining pane.
---@param tabpage number
---@param opts { keep: "original"|"modified", load_bufnr: number, original_path: string, modified_path: string, original_revision: string?, modified_revision: string?, highlight: boolean? }
local function show_single_file(tabpage, opts)
  local session = lifecycle.get_session(tabpage)
  if not session then
    return
  end

  lifecycle.update_layout(tabpage, "side-by-side")
  local orig_win, mod_win = lifecycle.get_windows(tabpage)

  -- Clear highlights from current session buffers
  local old_orig_buf, old_mod_buf = lifecycle.get_buffers(tabpage)
  if old_orig_buf then
    auto_refresh.disable(old_orig_buf)
    lifecycle.clear_highlights(old_orig_buf)
  end
  if old_mod_buf then
    auto_refresh.disable(old_mod_buf)
    lifecycle.clear_highlights(old_mod_buf)
  end

  -- Mark single-pane BEFORE closing window (prevents cleanup trigger)
  session.single_pane = true

  -- Close the unused window
  local keep_win, close_win
  if opts.keep == "modified" then
    keep_win, close_win = mod_win, orig_win
  else
    keep_win, close_win = orig_win, mod_win
  end

  if keep_win == close_win then
    close_win = nil
  end
  if (not keep_win or not vim.api.nvim_win_is_valid(keep_win)) and close_win and vim.api.nvim_win_is_valid(close_win) then
    keep_win = close_win
    close_win = nil
  end

  if close_win and vim.api.nvim_win_is_valid(close_win) then
    vim.w[close_win].codediff_restore = nil
    vim.api.nvim_win_close(close_win, true)
    close_win = nil
  end

  -- Load the file into the kept window
  if keep_win and vim.api.nvim_win_is_valid(keep_win) then
    vim.api.nvim_win_set_buf(keep_win, opts.load_bufnr)
    welcome_window.sync(keep_win)

    if opts.keep == "original" then
      session.original_win = keep_win
      session.modified_win = nil
    else
      session.original_win = nil
      session.modified_win = keep_win
    end

    -- Create a scratch buffer as placeholder for the empty side
    local empty_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[empty_buf].buftype = "nofile"

    local orig_bufnr = opts.keep == "original" and opts.load_bufnr or empty_buf
    local mod_bufnr = opts.keep == "modified" and opts.load_bufnr or empty_buf

    lifecycle.update_buffers(tabpage, orig_bufnr, mod_bufnr)
    lifecycle.update_paths(tabpage, path.make_ref(opts.original_path or "", session.git_root), path.make_ref(opts.modified_path or "", session.git_root))
    lifecycle.update_revisions(tabpage, opts.original_revision, opts.modified_revision)
    lifecycle.update_diff_result(tabpage, { changes = {}, moves = {} })
    session.single_side = opts.highlight ~= false and opts.keep or nil
    if session.single_side then
      core.render_whole_file(opts.load_bufnr, session.single_side)
    end

    local view_keymaps = require("codediff.ui.view.keymaps")
    view_keymaps.setup_all_keymaps(tabpage, orig_bufnr, mod_bufnr, session.mode == "explorer")
  end

  layout.arrange(tabpage)
  if keep_win and vim.api.nvim_win_is_valid(keep_win) then
    welcome_window.sync_later(keep_win)
  end
end

-- Load a real file from disk, return bufnr
local function load_real_file(file_path)
  local bufnr = vim.fn.bufadd(file_path)
  vim.fn.bufload(bufnr)
  return bufnr
end

-- Load a virtual file from git revision, return bufnr
local function load_virtual_file(git_root, revision, file_path)
  local virtual_file_mod = require("codediff.core.virtual_file")
  local url = virtual_file_mod.create_url(git_root, revision, file_path)
  local bufnr = vim.fn.bufadd(url)
  vim.fn.bufload(bufnr)
  return bufnr
end

--- Show an untracked file (status "??") — modified pane only
function M.show_untracked_file(tabpage, file_path)
  show_single_file(tabpage, {
    keep = "modified",
    load_bufnr = load_real_file(file_path),
    file_path = file_path,
    modified_path = file_path,
  })
end

--- Show a deleted file (status "D", working tree) — original pane only
function M.show_deleted_file(tabpage, git_root, file_path, abs_path, group)
  local revision = (group == "staged") and "HEAD" or ":0"
  show_single_file(tabpage, {
    keep = "original",
    load_bufnr = load_virtual_file(git_root, revision, file_path),
    file_path = abs_path,
    load_revision = revision,
    load_git_root = git_root,
    rel_path = file_path,
    original_path = abs_path,
    original_revision = revision,
  })
end

--- Show an added virtual file (status "A") — modified pane only
function M.show_added_virtual_file(tabpage, git_root, file_path, revision)
  show_single_file(tabpage, {
    keep = "modified",
    load_bufnr = load_virtual_file(git_root, revision, file_path),
    file_path = file_path,
    load_revision = revision,
    load_git_root = git_root,
    rel_path = file_path,
    modified_path = file_path,
    modified_revision = revision,
  })
end

--- Show a deleted virtual file (status "D", two-revision mode) — original pane only
function M.show_deleted_virtual_file(tabpage, git_root, file_path, revision)
  show_single_file(tabpage, {
    keep = "original",
    load_bufnr = load_virtual_file(git_root, revision, file_path),
    file_path = file_path,
    load_revision = revision,
    load_git_root = git_root,
    rel_path = file_path,
    original_path = file_path,
    original_revision = revision,
  })
end

--- Show the welcome page in a single pane (modified side)
function M.show_welcome(tabpage, load_bufnr)
  show_single_file(tabpage, {
    keep = "modified",
    highlight = false,
    load_bufnr = load_bufnr,
  })
end

return M
