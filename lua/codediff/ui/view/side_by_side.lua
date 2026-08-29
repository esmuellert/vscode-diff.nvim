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
local show_real_file_buffer = helpers.show_real_file_buffer
local open_real_file = helpers.open_real_file
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
--- True when the panel opens before any file is chosen, so the panes start
--- empty and the panel fills them on first selection.
--- @param session_config SessionConfig
--- @return boolean
local function is_panel_placeholder(session_config)
  local panel_cfg = session_config.panel
  if not panel_cfg then
    return false
  end
  if panel_cfg.name == "history" then
    return panel_cfg.data ~= nil
  end
  if panel_cfg.name == "explorer" then
    -- Empty paths, or dir mode, which has no git_root but does have panel data.
    return path.is_empty(session_config.original) or (not session_config.git_root and panel_cfg.data ~= nil)
  end
  return false
end

--- Split direction that lands the modified pane on the side the user asked for.
--- Explicit rather than relying on 'splitright'.
--- @return string
local function diff_split_cmd()
  return config.options.diff.original_position == "right" and "leftabove vsplit" or "rightbelow vsplit"
end

--- Open the two panes with throwaway scratch buffers, for a session whose
--- content arrives later via the panel.
--- @param tabpage number
--- @return number original_win, number modified_win, table original_info, table modified_info
local function open_placeholder_panes(tabpage)
  local original_win = vim.api.nvim_get_current_win()
  vim.cmd(diff_split_cmd())
  local modified_win = vim.api.nvim_get_current_win()

  -- A buffer each, so the tab's initial buffer can be deleted afterwards.
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

  return original_win, modified_win, { bufnr = orig_scratch }, { bufnr = mod_scratch }
end

--- Show one side's content in `win`, whether it is a git revision or a real file.
--- @param win number
--- @param info table From prepare_buffer
--- @param is_virtual boolean
local function load_side(win, info, is_virtual)
  if is_virtual then
    if info.needs_edit then
      vim.cmd("edit! " .. vim.fn.fnameescape(info.target))
      info.bufnr = vim.api.nvim_get_current_buf()
    else
      vim.api.nvim_win_set_buf(win, info.bufnr)
    end
  elseif info.needs_edit then
    info.bufnr = open_real_file(win, info.target)
  else
    show_real_file_buffer(win, info.bufnr)
  end
end

--- Open the two panes with the diff's actual content loaded.
--- @param session_config SessionConfig
--- @return number original_win, number modified_win, table original_info, table modified_info
local function open_diff_panes(session_config)
  local original_is_virtual = is_virtual_revision(session_config.original_revision)
  local modified_is_virtual = is_virtual_revision(session_config.modified_revision)

  local original_info = prepare_buffer(original_is_virtual, session_config.git_root, session_config.original_revision, session_config.original)
  local modified_info = prepare_buffer(modified_is_virtual, session_config.git_root, session_config.modified_revision, session_config.modified)

  local original_win = vim.api.nvim_get_current_win()
  load_side(original_win, original_info, original_is_virtual)

  vim.cmd(diff_split_cmd())
  local modified_win = vim.api.nvim_get_current_win()
  load_side(modified_win, modified_info, modified_is_virtual)

  welcome_window.sync(original_win)
  welcome_window.sync(modified_win)

  return original_win, modified_win, original_info, modified_info
end

--- Window options both diff panes get. 'wrap' is load-bearing: the scroll-sync
--- maps one buffer line to one screen row. 'number'/'relativenumber' are left
--- alone so the user's own settings survive.
--- @param original_win number
--- @param modified_win number
local function apply_pane_options(original_win, modified_win)
  local win_opts = {
    cursorline = true,
    wrap = false,
    list = false,
  }
  for opt, val in pairs(win_opts) do
    vim.wo[original_win][opt] = val
    vim.wo[modified_win][opt] = val
  end
end

--- Reapply-keymaps callback stored on the session, so a shape change (panel
--- appearing, layout toggle) can reinstall the right mappings.
--- @param tabpage number
--- @param opts? table { conflict: boolean }
--- @return function
local function make_reapply_keymaps(tabpage, opts)
  local is_conflict = opts and opts.conflict or false
  return function()
    local ob, mb = lifecycle.get_buffers(tabpage)
    if not ob or not mb then
      return
    end
    if is_conflict then
      setup_all_keymaps(tabpage, ob, mb, false)
      require("codediff.ui.conflict").setup_keymaps(tabpage)
    else
      setup_all_keymaps(tabpage, ob, mb, lifecycle.get_panel_name(tabpage) == "explorer")
    end
  end
end

--- Attach the panels, announce the view, and describe it to the caller.
--- @param tabpage number
--- @param session_config SessionConfig
--- @param original_win number
--- @param modified_win number
--- @param original_info table
--- @param modified_info table
--- @return table
local function finish_create(tabpage, session_config, original_win, modified_win, original_info, modified_info)
  panel.setup_explorer(tabpage, session_config, original_win, modified_win)
  panel.setup_history(tabpage, session_config, original_win, modified_win)

  vim.api.nvim_exec_autocmds("User", {
    pattern = "CodeDiffOpen",
    modeline = false,
    data = {
      tabpage = tabpage,
      mode = lifecycle.event_mode(session_config.panel),
    },
  })

  return {
    original_buf = original_info.bufnr,
    modified_buf = modified_info.bufnr,
    original_win = original_win,
    modified_win = modified_win,
  }
end

--- Render a 3-way merge: fetch the merge base, diff both sides against it,
--- then register the session and open the result pane.
--- @param ctx table { tabpage, session_config, wins, infos, lines, on_ready }
local function render_conflict_view(ctx)
  local git = require("codediff.core.git")
  local session_config = ctx.session_config
  local tabpage = ctx.tabpage
  local original_win, modified_win = ctx.original_win, ctx.modified_win
  local original_info, modified_info = ctx.original_info, ctx.modified_info

  git.get_file_content(":1", session_config.git_root, session_config.original.relative, function(err, base_lines)
    -- Add/add conflicts (AA) have no base version; treat it as empty.
    if err then
      base_lines = {}
    end

    vim.schedule(function()
      local conflict_diffs = compute_and_render_conflict(
        original_info.bufnr,
        modified_info.bufnr,
        base_lines,
        ctx.original_lines,
        ctx.modified_lines,
        original_win,
        modified_win,
        config.options.diff.jump_to_first_change
      )
      if not conflict_diffs then
        return
      end

      lifecycle.create_session(tabpage, {
        panel = session_config.panel,
        merge = session_config.conflict,
        git_root = session_config.git_root,
        original = session_config.original,
        modified = session_config.modified,
        original_revision = session_config.original_revision,
        modified_revision = session_config.modified_revision,
        original_bufnr = original_info.bufnr,
        modified_bufnr = modified_info.bufnr,
        original_win = original_win,
        modified_win = modified_win,
        lines_diff = conflict_diffs.base_to_modified_diff,
        exit_on_close = session_config.exit_on_close,
        reapply_keymaps = make_reapply_keymaps(tabpage, { conflict = true }),
      })

      local success = setup_conflict_result_window(tabpage, session_config, original_win, modified_win, base_lines, conflict_diffs, false)
      if success then
        setup_all_keymaps(tabpage, original_info.bufnr, modified_info.bufnr, false)
        -- After setup_all_keymaps, so the conflict mappings win.
        require("codediff.ui.conflict").setup_keymaps(tabpage)
      end

      if ctx.on_ready then
        ctx.on_ready()
      end
    end)
  end)
end

--- Render an ordinary two-pane diff and register the session.
--- @param ctx table { tabpage, session_config, wins, infos, lines, virtual flags, on_ready }
local function render_diff_view(ctx)
  local session_config = ctx.session_config
  local tabpage = ctx.tabpage
  local original_info, modified_info = ctx.original_info, ctx.modified_info

  local lines_diff = compute_and_render(
    original_info.bufnr,
    modified_info.bufnr,
    ctx.original_lines,
    ctx.modified_lines,
    ctx.original_is_virtual,
    ctx.modified_is_virtual,
    ctx.original_win,
    ctx.modified_win,
    config.options.diff.jump_to_first_change
  )
  if not lines_diff then
    return
  end

  lifecycle.create_session(tabpage, {
    panel = session_config.panel,
    merge = session_config.conflict,
    git_root = session_config.git_root,
    original = session_config.original,
    modified = session_config.modified,
    original_revision = session_config.original_revision,
    modified_revision = session_config.modified_revision,
    original_bufnr = original_info.bufnr,
    modified_bufnr = modified_info.bufnr,
    original_win = ctx.original_win,
    modified_win = ctx.modified_win,
    lines_diff = lines_diff,
    exit_on_close = session_config.exit_on_close,
    reapply_keymaps = make_reapply_keymaps(tabpage),
  })

  -- Real file buffers only; virtual ones never change under us.
  setup_auto_refresh(original_info.bufnr, modified_info.bufnr, ctx.original_is_virtual, ctx.modified_is_virtual)
  setup_all_keymaps(tabpage, original_info.bufnr, modified_info.bufnr, false)
  require("codediff.ui.follow_working_file").enable(tabpage, ctx.original_is_virtual, ctx.modified_is_virtual)

  if ctx.on_ready then
    ctx.on_ready()
  end
end

--- Run `render` once both panes hold their final content.
--- Virtual buffers load asynchronously via BufReadCmd, so wait for the load
--- event for each virtual side; real files only need the pending :edit to
--- finish.
--- @param tabpage number
--- @param original_info table
--- @param modified_info table
--- @param original_is_virtual boolean
--- @param modified_is_virtual boolean
--- @param render function
local function render_when_loaded(tabpage, original_info, modified_info, original_is_virtual, modified_is_virtual, render)
  if not (original_is_virtual or modified_is_virtual) then
    vim.schedule(render)
    return
  end

  local group = vim.api.nvim_create_augroup("CodeDiffVirtualFileHighlight_" .. tabpage, { clear = true })
  local loaded = {}

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffVirtualFileLoaded",
    callback = function(event)
      local buf = event.data and event.data.buf
      if not buf then
        return
      end
      local ours = (original_is_virtual and buf == original_info.bufnr) or (modified_is_virtual and buf == modified_info.bufnr)
      if not ours then
        return
      end
      loaded[buf] = true

      local ready = true
      if original_is_virtual and not loaded[original_info.bufnr] then
        ready = false
      end
      if modified_is_virtual and not loaded[modified_info.bufnr] then
        ready = false
      end
      if ready then
        vim.schedule(render)
        vim.api.nvim_del_augroup_by_id(group)
      end
    end,
  })
end

function M.create(session_config, filetype, on_ready)
  vim.cmd("tabnew")
  local tabpage = vim.api.nvim_get_current_tabpage()
  local initial_buf = vim.api.nvim_get_current_buf()

  local placeholder = is_panel_placeholder(session_config)
  local original_win, modified_win, original_info, modified_info

  if placeholder then
    original_win, modified_win, original_info, modified_info = open_placeholder_panes(tabpage)
  else
    original_win, modified_win, original_info, modified_info = open_diff_panes(session_config)
  end

  -- Clean up initial buffer
  if vim.api.nvim_buf_is_valid(initial_buf) and initial_buf ~= original_info.bufnr and initial_buf ~= modified_info.bufnr then
    pcall(vim.api.nvim_buf_delete, initial_buf, { force = true })
  end

  apply_pane_options(original_win, modified_win)

  if placeholder then
    -- The panel populates this session on first file selection.
    lifecycle.create_session(tabpage, {
      panel = session_config.panel,
      merge = session_config.conflict,
      git_root = session_config.git_root,
      original = "", -- Empty paths indicate placeholder
      modified = "",
      original_revision = nil,
      modified_revision = nil,
      original_bufnr = original_info.bufnr,
      modified_bufnr = modified_info.bufnr,
      original_win = original_win,
      modified_win = modified_win,
      lines_diff = {}, -- Empty diff result - will be updated on first file selection
      exit_on_close = session_config.exit_on_close,
      reapply_keymaps = make_reapply_keymaps(tabpage),
    })
  else
    local original_is_virtual = is_virtual_revision(session_config.original_revision)
    local modified_is_virtual = is_virtual_revision(session_config.modified_revision)

    local render = function()
      -- The panes may have been closed, or the buffers wiped, while we waited.
      if not vim.api.nvim_win_is_valid(original_win) or not vim.api.nvim_win_is_valid(modified_win) then
        return
      end
      if not vim.api.nvim_buf_is_valid(original_info.bufnr) or not vim.api.nvim_buf_is_valid(modified_info.bufnr) then
        return
      end

      -- Called from vim.schedule, possibly with another tab current. syncbind
      -- and friends act on the current tab, so switch to ours first.
      local target_tab = vim.api.nvim_win_get_tabpage(modified_win)
      if vim.api.nvim_get_current_tabpage() ~= target_tab then
        vim.api.nvim_set_current_tabpage(target_tab)
      end

      -- Read from the buffers, the single source of truth.
      local ctx = {
        tabpage = tabpage,
        session_config = session_config,
        original_win = original_win,
        modified_win = modified_win,
        original_info = original_info,
        modified_info = modified_info,
        original_lines = vim.api.nvim_buf_get_lines(original_info.bufnr, 0, -1, false),
        modified_lines = vim.api.nvim_buf_get_lines(modified_info.bufnr, 0, -1, false),
        original_is_virtual = original_is_virtual,
        modified_is_virtual = modified_is_virtual,
        on_ready = on_ready,
      }

      if session_config.conflict then
        render_conflict_view(ctx)
      else
        render_diff_view(ctx)
      end
    end

    render_when_loaded(tabpage, original_info, modified_info, original_is_virtual, modified_is_virtual, render)
  end

  return finish_create(tabpage, session_config, original_win, modified_win, original_info, modified_info)
end

-- ============================================================================
-- Update
-- ============================================================================

---@param tabpage number
---@param session_config SessionConfig
---@param auto_scroll_to_first_hunk boolean?
---@return boolean
--- Put one side's content into `win` during an update, reusing the buffer when
--- it is still alive and re-editing when it is not.
--- Unlike load_side, used on create, this also has to cope with the buffer
--- having been wiped since the session was built.
--- @param win number
--- @param info table From prepare_buffer; info.bufnr is updated in place
--- @param is_virtual boolean
local function reload_side(win, info, is_virtual)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local function edit_in_place()
    vim.api.nvim_set_current_win(win)
    vim.cmd("edit! " .. vim.fn.fnameescape(info.target))
    info.bufnr = vim.api.nvim_get_current_buf()
  end

  if info.needs_edit then
    if not is_virtual then
      info.bufnr = open_real_file(win, info.target)
    elseif info.bufnr and vim.api.nvim_buf_is_valid(info.bufnr) then
      vim.api.nvim_win_set_buf(win, info.bufnr)
      virtual_file.refresh_buffer(info.bufnr)
    else
      edit_in_place()
    end
    return
  end

  if vim.api.nvim_buf_is_valid(info.bufnr) then
    if is_virtual then
      vim.api.nvim_win_set_buf(win, info.bufnr)
    else
      show_real_file_buffer(win, info.bufnr)
    end
  elseif is_virtual then
    edit_in_place()
  else
    info.bufnr = open_real_file(win, info.target)
  end
end

--- Run `render` once every side that needs loading has loaded.
--- @param tabpage number
--- @param original_info table
--- @param modified_info table
--- @param wait_state table { original: boolean, modified: boolean }
--- @param render function
local function render_when_reloaded(tabpage, original_info, modified_info, wait_state, render)
  if not (wait_state.original or wait_state.modified) then
    return
  end

  local group = vim.api.nvim_create_augroup("CodeDiffVirtualFileUpdate_" .. tabpage, { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffVirtualFileLoaded",
    callback = function(event)
      local buf = event.data and event.data.buf
      if not buf then
        return
      end
      if wait_state.original and buf == original_info.bufnr then
        wait_state.original = false
      end
      if wait_state.modified and buf == modified_info.bufnr then
        wait_state.modified = false
      end
      if not wait_state.original and not wait_state.modified then
        vim.schedule(render)
        vim.api.nvim_del_augroup_by_id(group)
      end
    end,
  })
end

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

  -- Retargeting can move a session between a conflicted file and an ordinary
  -- one, so the merge flag follows the incoming config.
  lifecycle.update_merge(tabpage, session_config.conflict)

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
            local is_explorer_mode = session.panel and session.panel.name == "explorer"
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

        local is_explorer_mode = session.panel and session.panel.name == "explorer"
        setup_all_keymaps(tabpage, original_info.bufnr, modified_info.bufnr, is_explorer_mode)

        -- Restore focus to the window that was active before update
        if saved_current_win and vim.api.nvim_win_is_valid(saved_current_win) then
          vim.api.nvim_set_current_win(saved_current_win)
        end
      end
    end
  end

  -- Wait for virtual content before rendering; real files are ready already.
  render_when_reloaded(tabpage, original_info, modified_info, wait_state, render_everything)
  reload_side(original_win, original_info, original_is_virtual)
  reload_side(modified_win, modified_info, modified_is_virtual)

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

  -- Nothing to wait for: render now. Otherwise render_when_reloaded does it.
  if not (wait_state.original or wait_state.modified) then
    vim.schedule(render_everything)
  end

  return true
end

-- ============================================================================
-- Single-file display (no diff) for explorer special cases
-- ============================================================================

--- True when the pane already shows exactly what this call would render.
--- Explorer refreshes re-select the file that is already open. For real diffs
--- on_file_select short-circuits that, but untracked/added/deleted files return
--- before reaching its guard, so the window was torn down and rebuilt on every
--- refresh, and the layout pass at the end of the rebuild discarded any pane
--- the user had resized. Comparing the displayed buffer covers path and
--- revision at once, since virtual revisions resolve to distinct buffers.
---@param session table
---@param opts table
---@return boolean
local function single_file_unchanged(session, opts)
  if not session.single_pane then
    return false
  end
  if session.single_side ~= (opts.highlight ~= false and opts.keep or nil) then
    return false
  end
  local keep_win = opts.keep == "original" and session.original_win or session.modified_win
  local other_win = opts.keep == "original" and session.modified_win or session.original_win
  if other_win and vim.api.nvim_win_is_valid(other_win) then
    return false
  end
  if not keep_win or not vim.api.nvim_win_is_valid(keep_win) then
    return false
  end
  return vim.api.nvim_win_get_buf(keep_win) == opts.load_bufnr
end

--- Core implementation for showing a single file without diff.
--- Closes the empty pane and loads the file into the remaining pane.
---@param tabpage number
---@param opts { keep: "original"|"modified", load_bufnr: number, original_path: string, modified_path: string, original_revision: string?, modified_revision: string?, highlight: boolean? }
local function show_single_file(tabpage, opts)
  local session = lifecycle.get_session(tabpage)
  if not session then
    return
  end

  if single_file_unchanged(session, opts) then
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

  -- Leaving conflict mode: close the result window too, mirroring M.update.
  -- Without this the 3rd conflict pane survives under the single-file view, and
  -- returning to the conflict file reuses that stale window whose buffer still
  -- has unsaved merge edits, so `:edit` fails with E37. Closing is forced so it
  -- also works when 'hidden' is off; the buffer only becomes hidden, never
  -- unloaded, so in-progress merge edits are preserved.
  local _, old_result_win = lifecycle.get_result(tabpage)
  if old_result_win and vim.api.nvim_win_is_valid(old_result_win) then
    vim.w[old_result_win].codediff_restore = nil
    pcall(vim.api.nvim_win_close, old_result_win, true)
  end
  lifecycle.set_result(tabpage, nil, nil)

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

  -- Load the file into the kept window BEFORE closing the other one. Virtual
  -- buffers (from load_virtual_file) carry `bufhidden = "wipe"` so they get
  -- wiped as soon as they have no window; closing close_win first would leave
  -- the freshly-created virtual buffer with no window, wiping it before we can
  -- set it into keep_win — producing "Invalid buffer id" (#498).
  if keep_win and vim.api.nvim_win_is_valid(keep_win) then
    show_real_file_buffer(keep_win, opts.load_bufnr)
  end

  if close_win and vim.api.nvim_win_is_valid(close_win) then
    vim.w[close_win].codediff_restore = nil
    vim.api.nvim_win_close(close_win, true)
    close_win = nil
  end

  if keep_win and vim.api.nvim_win_is_valid(keep_win) then
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
    view_keymaps.setup_all_keymaps(tabpage, orig_bufnr, mod_bufnr, session.panel ~= nil and session.panel.name == "explorer")
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
