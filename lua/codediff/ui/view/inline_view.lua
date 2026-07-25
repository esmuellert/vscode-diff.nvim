-- Inline diff view engine: single-window diff with virtual line overlays
-- Parallel to side_by_side.lua — handles creation, updating, and re-rendering
local M = {}

local lifecycle = require("codediff.ui.lifecycle")
local auto_refresh = require("codediff.ui.auto_refresh")
local config = require("codediff.config")
local core = require("codediff.ui.core")
local path = require("codediff.core.path")
local diff_module = require("codediff.core.diff")
local inline = require("codediff.ui.inline")
local semantic = require("codediff.ui.semantic_tokens")
local layout = require("codediff.ui.layout")
local welcome_window = require("codediff.ui.view.welcome_window")

local helpers = require("codediff.ui.view.helpers")
local panel = require("codediff.ui.view.panel")
local is_virtual_revision = helpers.is_virtual_revision
local prepare_buffer = helpers.prepare_buffer

local function disable_refresh_and_clear_highlights(session)
  for _, bufnr in pairs({ session.original_bufnr, session.modified_bufnr }) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      auto_refresh.disable(bufnr)
      lifecycle.clear_highlights(bufnr)
    end
  end
end

-- ============================================================================
-- Compute diff and render inline highlights
-- ============================================================================

local function compute_and_render_inline(
  modified_buf,
  original_buf,
  original_lines,
  modified_lines,
  original_is_virtual,
  modified_is_virtual,
  modified_win,
  auto_scroll_to_first_hunk
)
  local diff_options = {
    max_computation_time_ms = config.options.diff.max_computation_time_ms,
    ignore_trim_whitespace = config.options.diff.ignore_trim_whitespace,
    compute_moves = config.options.diff.compute_moves,
  }

  local lines_diff = diff_module.compute_diff(original_lines, modified_lines, diff_options)
  if not lines_diff then
    vim.notify("Failed to compute diff", vim.log.levels.ERROR)
    return nil
  end

  inline.render_inline_diff(modified_buf, lines_diff, original_lines, modified_lines)

  if original_is_virtual then
    semantic.apply_semantic_tokens(original_buf, modified_buf)
  end
  if modified_is_virtual then
    semantic.apply_semantic_tokens(modified_buf, original_buf)
  end

  if modified_win and vim.api.nvim_win_is_valid(modified_win) then
    vim.wo[modified_win].wrap = false
    if auto_scroll_to_first_hunk and lines_diff.changes and #lines_diff.changes > 0 then
      -- Honor session.pending_cursor_landing (cycle-hunks-across-files
      -- backward direction sets it to "last"; see ui/view/navigation.lua).
      -- Look up the session via the window's tabpage because this code can
      -- run from a scheduled callback on a different tab.
      local lifecycle = require("codediff.ui.lifecycle")
      local tabpage = vim.api.nvim_win_get_tabpage(modified_win)
      local session = tabpage and lifecycle.get_session(tabpage) or nil
      local landing = session and session.pending_cursor_landing
      if session then
        session.pending_cursor_landing = nil
      end

      local target_line = landing == "last" and lines_diff.changes[#lines_diff.changes].modified.start_line or lines_diff.changes[1].modified.start_line
      pcall(vim.api.nvim_win_set_cursor, modified_win, { target_line, 0 })
      vim.api.nvim_set_current_win(modified_win)
      vim.cmd("normal! zz")
    end
  end

  return lines_diff
end

-- Helper: mark session as inline layout after creation
local function mark_inline(tabpage)
  lifecycle.update_layout(tabpage, "inline")
end

-- Helper: setup keymaps (uses the shared setup_all_keymaps which is layout-aware)
local function setup_keymaps(tabpage, orig_buf, mod_buf)
  local view_keymaps = require("codediff.ui.view.keymaps")
  local session = lifecycle.get_session(tabpage)
  local is_explorer = session and session.mode == "explorer"
  view_keymaps.setup_all_keymaps(tabpage, orig_buf, mod_buf, is_explorer)
end

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
  local modified_win = vim.api.nvim_get_current_win()
  local initial_buf = vim.api.nvim_get_current_buf()

  -- Check if this is an explorer/history placeholder
  local is_explorer_placeholder = session_config.mode == "explorer" and (path.is_empty(session_config.original) or (not session_config.git_root and session_config.explorer_data))
  local is_history_placeholder = session_config.mode == "history" and session_config.history_data

  if is_explorer_placeholder or is_history_placeholder then
    -- Placeholder: single window with scratch buffer, no diff yet
    local mod_scratch = vim.api.nvim_create_buf(false, true)
    vim.bo[mod_scratch].buftype = "nofile"
    pcall(vim.api.nvim_buf_set_name, mod_scratch, "CodeDiff " .. tabpage .. ".inline")
    vim.api.nvim_win_set_buf(modified_win, mod_scratch)
    welcome_window.sync(modified_win)

    local orig_scratch = vim.api.nvim_create_buf(false, true)
    vim.bo[orig_scratch].buftype = "nofile"

    if vim.api.nvim_buf_is_valid(initial_buf) and initial_buf ~= mod_scratch then
      pcall(vim.api.nvim_buf_delete, initial_buf, { force = true })
    end

    vim.wo[modified_win].cursorline = true
    vim.wo[modified_win].wrap = false

    lifecycle.create_session(
      tabpage,
      session_config.mode,
      session_config.git_root,
      "",
      "",
      nil,
      nil,
      orig_scratch,
      mod_scratch,
      modified_win,
      modified_win, -- both point to the single window
      {},
      function()
        local _, mb = lifecycle.get_buffers(tabpage)
        if mb then
          setup_keymaps(tabpage, orig_scratch, mb)
        end
      end,
      session_config.exit_on_close
    )

    mark_inline(tabpage)
    -- Setup panels via shared module
    panel.setup_explorer(tabpage, session_config, modified_win, modified_win)
    panel.setup_history(tabpage, session_config, modified_win, modified_win)

    layout.arrange(tabpage)

    vim.api.nvim_exec_autocmds("User", {
      pattern = "CodeDiffOpen",
      modeline = false,
      data = { tabpage = tabpage, mode = session_config.mode, layout = "inline" },
    })

    return { modified_buf = mod_scratch, original_buf = orig_scratch, modified_win = modified_win }
  end

  -- Normal (non-placeholder) inline view creation
  local original_is_virtual = is_virtual_revision(session_config.original_revision)
  local modified_is_virtual = is_virtual_revision(session_config.modified_revision)

  local original_info = prepare_buffer(original_is_virtual, session_config.git_root, session_config.original_revision, session_config.original)
  local modified_info = prepare_buffer(modified_is_virtual, session_config.git_root, session_config.modified_revision, session_config.modified)

  -- Load modified buffer into the visible window
  if modified_info.needs_edit then
    local cmd = modified_is_virtual and "edit! " or "edit "
    vim.cmd(cmd .. vim.fn.fnameescape(modified_info.target))
    modified_info.bufnr = vim.api.nvim_get_current_buf()
  else
    vim.api.nvim_win_set_buf(modified_win, modified_info.bufnr)
  end
  welcome_window.sync(modified_win)

  -- Load original buffer (hidden — never displayed in a window)
  if original_is_virtual and original_info.needs_edit then
    -- Can't use :edit with codediff:// URIs because bufhidden=wipe destroys
    -- the buffer when no window displays it. Use scratch buffer instead.
    local orig_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[orig_buf].buftype = "nofile"
    original_info.bufnr = orig_buf
  elseif original_info.needs_edit then
    local bufnr = vim.fn.bufadd(original_info.target)
    vim.fn.bufload(bufnr)
    original_info.bufnr = bufnr
  end

  if vim.api.nvim_buf_is_valid(initial_buf) and initial_buf ~= modified_info.bufnr and initial_buf ~= original_info.bufnr then
    pcall(vim.api.nvim_buf_delete, initial_buf, { force = true })
  end

  vim.wo[modified_win].cursorline = true
  vim.wo[modified_win].wrap = false

  local render_everything = function()
    if not vim.api.nvim_win_is_valid(modified_win) then
      return
    end
    if not vim.api.nvim_buf_is_valid(original_info.bufnr) or not vim.api.nvim_buf_is_valid(modified_info.bufnr) then
      return
    end

    local original_lines = vim.api.nvim_buf_get_lines(original_info.bufnr, 0, -1, false)
    local modified_lines = vim.api.nvim_buf_get_lines(modified_info.bufnr, 0, -1, false)

    local lines_diff = compute_and_render_inline(
      modified_info.bufnr,
      original_info.bufnr,
      original_lines,
      modified_lines,
      original_is_virtual,
      modified_is_virtual,
      modified_win,
      config.options.diff.jump_to_first_change
    )

    if lines_diff then
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
        modified_win,
        modified_win,
        lines_diff,
        function()
          local _, mb = lifecycle.get_buffers(tabpage)
          if mb then
            setup_keymaps(tabpage, original_info.bufnr, mb)
          end
        end,
        session_config.exit_on_close
      )

      mark_inline(tabpage)

      auto_refresh.enable(original_info.bufnr)
      auto_refresh.enable(modified_info.bufnr)

      setup_keymaps(tabpage, original_info.bufnr, modified_info.bufnr)

      if on_ready then
        on_ready()
      end
    end
  end

  -- Async buffer loading
  if original_is_virtual then
    local git = require("codediff.core.git")
    git.get_file_content(session_config.original_revision, session_config.git_root, session_config.original.relative, function(err, lines)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(original_info.bufnr) then
          return
        end
        if err then
          lines = {}
        end
        vim.bo[original_info.bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(original_info.bufnr, 0, -1, false, lines)
        vim.bo[original_info.bufnr].modifiable = false

        if modified_is_virtual then
          local group = vim.api.nvim_create_augroup("CodeDiffInlineVirtualLoad_" .. tabpage, { clear = true })
          vim.api.nvim_create_autocmd("User", {
            group = group,
            pattern = "CodeDiffVirtualFileLoaded",
            callback = function(event)
              if event.data and event.data.buf == modified_info.bufnr then
                vim.schedule(render_everything)
                vim.api.nvim_del_augroup_by_id(group)
              end
            end,
          })
        else
          render_everything()
        end
      end)
    end)
  elseif modified_is_virtual then
    local group = vim.api.nvim_create_augroup("CodeDiffInlineVirtualLoad_" .. tabpage, { clear = true })
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "CodeDiffVirtualFileLoaded",
      callback = function(event)
        if event.data and event.data.buf == modified_info.bufnr then
          vim.schedule(render_everything)
          vim.api.nvim_del_augroup_by_id(group)
        end
      end,
    })
  else
    vim.schedule(render_everything)
  end

  -- Setup panels for non-placeholder explorer/history mode
  panel.setup_explorer(tabpage, session_config, modified_win, modified_win)
  panel.setup_history(tabpage, session_config, modified_win, modified_win)

  layout.arrange(tabpage)

  vim.api.nvim_exec_autocmds("User", {
    pattern = "CodeDiffOpen",
    modeline = false,
    data = { tabpage = tabpage, mode = session_config.mode, layout = "inline" },
  })

  return { modified_buf = modified_info.bufnr, original_buf = original_info.bufnr, modified_win = modified_win }
end

-- ============================================================================
-- Update (for explorer/history file switching)
-- ============================================================================

---@param tabpage number
---@param session_config SessionConfig
---@param auto_scroll_to_first_hunk boolean?
---@return boolean
function M.update(tabpage, session_config, auto_scroll_to_first_hunk)
  local saved_current_win = vim.api.nvim_get_current_win()

  local session = lifecycle.get_session(tabpage)
  if not session then
    return false
  end

  local modified_win = session.modified_win
  if not modified_win or not vim.api.nvim_win_is_valid(modified_win) then
    return false
  end

  -- ns_highlight/ns_filler may linger after toggling from side-by-side.
  disable_refresh_and_clear_highlights(session)

  session.single_side = nil
  lifecycle.update_diff_result(tabpage, nil)

  local original_is_virtual = is_virtual_revision(session_config.original_revision)
  local modified_is_virtual = is_virtual_revision(session_config.modified_revision)

  -- For inline mode, load ALL virtual buffers via git.get_file_content into scratch
  -- buffers instead of codediff:// URIs (avoids race conditions and bufhidden=wipe)

  local orig_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[orig_buf].buftype = "nofile"

  local mod_buf
  if modified_is_virtual then
    mod_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[mod_buf].buftype = "nofile"
    vim.bo[mod_buf].modifiable = true
    vim.api.nvim_win_set_buf(modified_win, mod_buf)
    local ft = vim.filetype.match({ filename = session_config.modified.absolute })
    if ft then
      vim.bo[mod_buf].filetype = ft
    end
  else
    local modified_info = prepare_buffer(false, session_config.git_root, nil, session_config.modified)
    if modified_info.needs_edit then
      local bufnr = vim.fn.bufadd(modified_info.target)
      vim.fn.bufload(bufnr)
      mod_buf = bufnr
    else
      mod_buf = modified_info.bufnr
      vim.api.nvim_buf_call(mod_buf, function()
        vim.cmd("checktime")
      end)
    end
    vim.api.nvim_win_set_buf(modified_win, mod_buf)
  end
  welcome_window.sync(modified_win)

  local should_auto_scroll = auto_scroll_to_first_hunk == true

  local render_everything = function()
    if not vim.api.nvim_win_is_valid(modified_win) then
      return
    end
    if not vim.api.nvim_buf_is_valid(orig_buf) or not vim.api.nvim_buf_is_valid(mod_buf) then
      return
    end

    local original_lines = vim.api.nvim_buf_get_lines(orig_buf, 0, -1, false)
    local modified_lines = vim.api.nvim_buf_get_lines(mod_buf, 0, -1, false)

    local lines_diff = compute_and_render_inline(mod_buf, orig_buf, original_lines, modified_lines, original_is_virtual, modified_is_virtual, modified_win, should_auto_scroll)

    if lines_diff then
      lifecycle.update_buffers(tabpage, orig_buf, mod_buf)
      lifecycle.update_git_root(tabpage, session_config.git_root)
      lifecycle.update_revisions(tabpage, session_config.original_revision, session_config.modified_revision)
      lifecycle.update_diff_result(tabpage, lines_diff)
      lifecycle.update_changedtick(tabpage, vim.api.nvim_buf_get_changedtick(orig_buf), vim.api.nvim_buf_get_changedtick(mod_buf))
      lifecycle.update_paths(tabpage, session_config.original, session_config.modified)

      auto_refresh.enable(orig_buf)
      auto_refresh.enable(mod_buf)

      setup_keymaps(tabpage, orig_buf, mod_buf)
      layout.arrange(tabpage)

      if saved_current_win and vim.api.nvim_win_is_valid(saved_current_win) then
        vim.api.nvim_set_current_win(saved_current_win)
      end
    end
  end

  -- Async loading with pending counter
  local pending = { original = original_is_virtual, modified = modified_is_virtual }
  local git = require("codediff.core.git")

  local function check_ready()
    if not pending.original and not pending.modified then
      render_everything()
    end
  end

  if original_is_virtual then
    git.get_file_content(
      session_config.original_revision,
      session_config.git_root,
      (session_config.original.relative ~= "" and session_config.original.relative) or session_config.modified.relative,
      function(err, lines)
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(orig_buf) then
            return
          end
          if err then
            lines = {}
          end
          vim.bo[orig_buf].modifiable = true
          vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, lines)
          vim.bo[orig_buf].modifiable = false
          pending.original = false
          check_ready()
        end)
      end
    )
  else
    local orig_path = (session_config.original.absolute ~= "" and session_config.original.absolute) or session_config.modified.absolute
    if orig_path and orig_path ~= "" then
      local real_bufnr = vim.fn.bufadd(orig_path)
      vim.fn.bufload(real_bufnr)
      local lines = vim.api.nvim_buf_get_lines(real_bufnr, 0, -1, false)
      vim.bo[orig_buf].modifiable = true
      vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, lines)
      vim.bo[orig_buf].modifiable = false
    end
    pending.original = false
  end

  if modified_is_virtual then
    git.get_file_content(session_config.modified_revision, session_config.git_root, session_config.modified.relative, function(err, lines)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(mod_buf) then
          return
        end
        if err then
          lines = {}
        end
        vim.bo[mod_buf].modifiable = true
        vim.api.nvim_buf_set_lines(mod_buf, 0, -1, false, lines)
        vim.bo[mod_buf].modifiable = false
        pending.modified = false
        check_ready()
      end)
    end)
  else
    pending.modified = false
  end

  if not pending.original and not pending.modified then
    vim.schedule(render_everything)
  end

  return true
end

-- ============================================================================
-- Re-render (for auto-refresh)
-- ============================================================================

function M.rerender(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session or session.layout ~= "inline" then
    return
  end

  local original_bufnr = session.original_bufnr
  local modified_bufnr = session.modified_bufnr

  if not vim.api.nvim_buf_is_valid(original_bufnr) or not vim.api.nvim_buf_is_valid(modified_bufnr) then
    return
  end

  local original_lines = vim.api.nvim_buf_get_lines(original_bufnr, 0, -1, false)
  local modified_lines = vim.api.nvim_buf_get_lines(modified_bufnr, 0, -1, false)

  local diff_options = {
    max_computation_time_ms = config.options.diff.max_computation_time_ms,
    ignore_trim_whitespace = config.options.diff.ignore_trim_whitespace,
    compute_moves = config.options.diff.compute_moves,
  }

  local lines_diff = diff_module.compute_diff(original_lines, modified_lines, diff_options)
  if lines_diff then
    inline.render_inline_diff(modified_bufnr, lines_diff, original_lines, modified_lines)
    lifecycle.update_diff_result(tabpage, lines_diff)
  end
end

-- ============================================================================
-- Show single file (no diff) for inline mode
-- ============================================================================

--- Display a single file in the inline diff window without any diff decorations.
--- Used for untracked (??), added (A), and deleted (D) files in explorer/history.
---@param tabpage number
---@param file_path string Path to load (absolute for real files)
---@param opts? { revision: string?, git_root: string?, rel_path: string?, side: "original"|"modified"? }
function M.show_single_file(tabpage, file_path, opts)
  opts = opts or {}
  local session = lifecycle.get_session(tabpage)
  if not session then
    return
  end
  local side = opts.side or "modified"

  lifecycle.update_layout(tabpage, "inline")
  local mod_win = session.modified_win
  if not mod_win or not vim.api.nvim_win_is_valid(mod_win) then
    return
  end

  -- Clear old inline decorations
  -- Disable old auto-refresh
  disable_refresh_and_clear_highlights(session)

  -- Load the file
  local file_bufnr
  if opts.revision and opts.git_root then
    -- Virtual file: reuse a buffer keyed by (git_root, revision, path) via the
    -- codediff:// URL scheme. This guarantees a stable bufnr across repeated
    -- calls (same fix as side_by_side.load_virtual_file). The BufReadCmd in
    -- core/virtual_file.lua handles content fetching and intentionally avoids
    -- setting filetype to prevent LSP attach crashes on the custom URI scheme.
    local virtual_file = require("codediff.core.virtual_file")
    local url = virtual_file.create_url(opts.git_root, opts.revision, opts.rel_path or file_path)
    file_bufnr = vim.fn.bufadd(url)
    vim.fn.bufload(file_bufnr)
    vim.api.nvim_win_set_buf(mod_win, file_bufnr)
    welcome_window.sync(mod_win)
  else
    -- Real file
    file_bufnr = vim.fn.bufadd(file_path)
    vim.fn.bufload(file_bufnr)
    vim.api.nvim_win_set_buf(mod_win, file_bufnr)
    welcome_window.sync(mod_win)
  end

  -- Update session state
  local empty_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[empty_buf].buftype = "nofile"

  local session_path = (opts.revision and opts.rel_path) and opts.rel_path or file_path
  local file_ref = path.make_ref(session_path, opts.git_root or session.git_root)
  local orig_bufnr = side == "original" and file_bufnr or empty_buf
  local mod_bufnr = side == "modified" and file_bufnr or empty_buf
  local original = side == "original" and file_ref or path.empty()
  local modified = side == "modified" and file_ref or path.empty()
  local original_revision = side == "original" and opts.revision or nil
  local modified_revision = side == "modified" and opts.revision or nil

  lifecycle.update_buffers(tabpage, orig_bufnr, mod_bufnr)
  lifecycle.update_paths(tabpage, original, modified)
  lifecycle.update_revisions(tabpage, original_revision, modified_revision)
  lifecycle.update_diff_result(tabpage, { changes = {}, moves = {} })
  session.single_side = side
  core.render_whole_file(file_bufnr, side)

  local view_keymaps = require("codediff.ui.view.keymaps")
  view_keymaps.setup_all_keymaps(tabpage, orig_bufnr, mod_bufnr, session.mode == "explorer")
  layout.arrange(tabpage)
  welcome_window.sync_later(mod_win)
end

--- Show the welcome page in the inline diff window
---@param tabpage number
---@param load_bufnr number Welcome buffer created by welcome.create_buffer
function M.show_welcome(tabpage, load_bufnr)
  local session = lifecycle.get_session(tabpage)
  if not session then
    return
  end

  lifecycle.update_layout(tabpage, "inline")
  local mod_win = session.modified_win
  if not mod_win or not vim.api.nvim_win_is_valid(mod_win) then
    return
  end

  disable_refresh_and_clear_highlights(session)
  session.single_side = nil

  vim.api.nvim_win_set_buf(mod_win, load_bufnr)
  welcome_window.sync(mod_win)

  local empty_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[empty_buf].buftype = "nofile"

  lifecycle.update_buffers(tabpage, empty_buf, load_bufnr)
  lifecycle.update_paths(tabpage, path.empty(), path.empty())
  lifecycle.update_revisions(tabpage, nil, nil)
  lifecycle.update_diff_result(tabpage, { changes = {}, moves = {} })

  local view_keymaps = require("codediff.ui.view.keymaps")
  view_keymaps.setup_all_keymaps(tabpage, empty_buf, load_bufnr, session.mode == "explorer")
  layout.arrange(tabpage)
  welcome_window.sync_later(mod_win)
end

return M
