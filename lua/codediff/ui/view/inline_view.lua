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
local is_panel_placeholder = helpers.is_panel_placeholder
local show_real_file_buffer = helpers.show_real_file_buffer
local open_real_file = helpers.open_real_file

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
  local is_explorer = session and session.panel ~= nil and session.panel.name == "explorer"
  view_keymaps.setup_all_keymaps(tabpage, orig_buf, mod_buf, is_explorer)
end

-- ============================================================================
-- Create
-- ============================================================================

---@param session_config SessionConfig
---@param filetype? string
---@param on_ready? function
---@return table|nil
--- Replace a scratch buffer's contents, restoring its read-only state.
--- Returns false when the buffer is gone, which is the caller's cue to stop:
--- the tab may have closed while the fetch was in flight.
--- @param bufnr number
--- @param lines string[]
--- @return boolean
local function set_scratch_lines(bufnr, lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  return true
end

--- An empty, unlisted, non-file buffer.
--- @return number
local function new_scratch()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  return bufnr
end

--- Options for the single inline pane. No 'list' here: side-by-side sets it
--- to keep the two panes visually identical, which does not apply to one pane.
--- @param win number
local function apply_pane_options(win)
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
end

--- Reapply-keymaps callback stored on the session.
--- @param tabpage number
--- @param original_bufnr number
--- @return function
local function make_reapply_keymaps(tabpage, original_bufnr)
  return function()
    local _, mb = lifecycle.get_buffers(tabpage)
    if mb then
      setup_keymaps(tabpage, original_bufnr, mb)
    end
  end
end

--- Attach the panels, lay the tab out, announce the view, and describe it.
--- @param tabpage number
--- @param session_config SessionConfig
--- @param modified_win number
--- @param original_bufnr number
--- @param modified_bufnr number
--- @return table
local function finish_create(tabpage, session_config, modified_win, original_bufnr, modified_bufnr)
  panel.setup_explorer(tabpage, session_config, modified_win, modified_win)
  panel.setup_history(tabpage, session_config, modified_win, modified_win)

  layout.arrange(tabpage)

  vim.api.nvim_exec_autocmds("User", {
    pattern = "CodeDiffOpen",
    modeline = false,
    data = { tabpage = tabpage, mode = lifecycle.event_mode(session_config.panel), layout = "inline" },
  })

  return { modified_buf = modified_bufnr, original_buf = original_bufnr, modified_win = modified_win }
end

--- Open the single pane with a scratch buffer, for a session whose content
--- arrives later via the panel. The hidden original side gets a scratch buffer
--- too, so the session always has two buffers to talk about.
--- @param tabpage number
--- @param modified_win number
--- @return number original_bufnr, number modified_bufnr
local function open_placeholder_pane(tabpage, modified_win)
  local mod_scratch = new_scratch()
  pcall(vim.api.nvim_buf_set_name, mod_scratch, "CodeDiff " .. tabpage .. ".inline")
  vim.api.nvim_win_set_buf(modified_win, mod_scratch)
  welcome_window.sync(modified_win)

  return new_scratch(), mod_scratch
end

--- Show the modified side in the visible pane.
--- @param win number
--- @param info table From prepare_buffer; info.bufnr is updated in place
--- @param is_virtual boolean
local function load_visible_side(win, info, is_virtual)
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
  welcome_window.sync(win)
end

--- Materialise the original side, which inline never puts in a window.
--- A virtual original cannot use :edit — codediff:// buffers carry
--- bufhidden=wipe, so with no window showing them they are destroyed at once.
--- It gets an empty scratch buffer that the async fetch fills instead.
--- @param info table From prepare_buffer; info.bufnr is updated in place
--- @param is_virtual boolean
local function load_hidden_original(info, is_virtual)
  if is_virtual and info.needs_edit then
    info.bufnr = new_scratch()
  elseif info.needs_edit then
    local bufnr = vim.fn.bufadd(info.target)
    vim.fn.bufload(bufnr)
    info.bufnr = bufnr
  end
end

--- Call `render` once the modified buffer's virtual content has loaded.
--- @param tabpage number
--- @param modified_bufnr number
--- @param render function
local function render_after_modified_loads(tabpage, modified_bufnr, render)
  local group = vim.api.nvim_create_augroup("CodeDiffInlineVirtualLoad_" .. tabpage, { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffVirtualFileLoaded",
    callback = function(event)
      if event.data and event.data.buf == modified_bufnr then
        vim.schedule(render)
        vim.api.nvim_del_augroup_by_id(group)
      end
    end,
  })
end

--- Run `render` once both sides hold their content.
--- The original side, when virtual, is fetched here rather than through
--- BufReadCmd, because it has no window to trigger one.
--- @param ctx table { tabpage, session_config, original_info, modified_info, virtual flags }
--- @param render function
local function render_when_loaded(ctx, render)
  local original_info, modified_info = ctx.original_info, ctx.modified_info

  if not ctx.original_is_virtual then
    if ctx.modified_is_virtual then
      render_after_modified_loads(ctx.tabpage, modified_info.bufnr, render)
    else
      vim.schedule(render)
    end
    return
  end

  local git = require("codediff.core.git")
  local session_config = ctx.session_config
  git.get_file_content(session_config.original_revision, session_config.git_root, session_config.original.relative, function(err, lines)
    vim.schedule(function()
      if not set_scratch_lines(original_info.bufnr, err and {} or lines) then
        return
      end

      if ctx.modified_is_virtual then
        render_after_modified_loads(ctx.tabpage, modified_info.bufnr, render)
      else
        render()
      end
    end)
  end)
end

function M.create(session_config, filetype, on_ready)
  vim.cmd("tabnew")
  local tabpage = vim.api.nvim_get_current_tabpage()
  local modified_win = vim.api.nvim_get_current_win()
  local initial_buf = vim.api.nvim_get_current_buf()

  --- Drop the tab's starting buffer once the real ones are in place.
  local function drop_initial_buf(...)
    for _, keep in ipairs({ ... }) do
      if initial_buf == keep then
        return
      end
    end
    if vim.api.nvim_buf_is_valid(initial_buf) then
      pcall(vim.api.nvim_buf_delete, initial_buf, { force = true })
    end
  end

  if is_panel_placeholder(session_config) then
    local orig_scratch, mod_scratch = open_placeholder_pane(tabpage, modified_win)
    drop_initial_buf(mod_scratch)
    apply_pane_options(modified_win)

    -- The panel populates this session on first file selection.
    lifecycle.create_session(tabpage, {
      panel = session_config.panel,
      merge = session_config.conflict,
      git_root = session_config.git_root,
      original = "",
      modified = "",
      original_revision = nil,
      modified_revision = nil,
      original_bufnr = orig_scratch,
      modified_bufnr = mod_scratch,
      original_win = modified_win,
      modified_win = modified_win, -- both point to the single window
      lines_diff = {},
      exit_on_close = session_config.exit_on_close,
      reapply_keymaps = make_reapply_keymaps(tabpage, orig_scratch),
    })

    mark_inline(tabpage)
    return finish_create(tabpage, session_config, modified_win, orig_scratch, mod_scratch)
  end

  local original_is_virtual = is_virtual_revision(session_config.original_revision)
  local modified_is_virtual = is_virtual_revision(session_config.modified_revision)

  local original_info = prepare_buffer(original_is_virtual, session_config.git_root, session_config.original_revision, session_config.original)
  local modified_info = prepare_buffer(modified_is_virtual, session_config.git_root, session_config.modified_revision, session_config.modified)

  load_visible_side(modified_win, modified_info, modified_is_virtual)
  load_hidden_original(original_info, original_is_virtual)

  drop_initial_buf(modified_info.bufnr, original_info.bufnr)
  apply_pane_options(modified_win)

  local render = function()
    if not vim.api.nvim_win_is_valid(modified_win) then
      return
    end
    if not vim.api.nvim_buf_is_valid(original_info.bufnr) or not vim.api.nvim_buf_is_valid(modified_info.bufnr) then
      return
    end

    local lines_diff = compute_and_render_inline(
      modified_info.bufnr,
      original_info.bufnr,
      vim.api.nvim_buf_get_lines(original_info.bufnr, 0, -1, false),
      vim.api.nvim_buf_get_lines(modified_info.bufnr, 0, -1, false),
      original_is_virtual,
      modified_is_virtual,
      modified_win,
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
      original_win = modified_win,
      modified_win = modified_win,
      lines_diff = lines_diff,
      exit_on_close = session_config.exit_on_close,
      reapply_keymaps = make_reapply_keymaps(tabpage, original_info.bufnr),
    })

    mark_inline(tabpage)

    auto_refresh.enable(original_info.bufnr)
    auto_refresh.enable(modified_info.bufnr)

    setup_keymaps(tabpage, original_info.bufnr, modified_info.bufnr)

    -- Keep the diff pointed at the working window's file if it changes. Same
    -- as the side-by-side path: the behaviour belongs to the session shape,
    -- not to a layout.
    require("codediff.ui.follow_working_file").enable(tabpage, original_is_virtual, modified_is_virtual)

    if on_ready then
      on_ready()
    end
  end

  render_when_loaded({
    tabpage = tabpage,
    session_config = session_config,
    original_info = original_info,
    modified_info = modified_info,
    original_is_virtual = original_is_virtual,
    modified_is_virtual = modified_is_virtual,
  }, render)

  return finish_create(tabpage, session_config, modified_win, original_info.bufnr, modified_info.bufnr)
end

-- ============================================================================
-- Update (for explorer/history file switching)
-- ============================================================================

--- Fetch a revision from git into a scratch buffer, then signal completion.
--- Signals nothing if the buffer died while the fetch was in flight.
--- @param revision string
--- @param git_root string
--- @param relative string
--- @param bufnr number
--- @param done function
local function fetch_into_scratch(revision, git_root, relative, bufnr, done)
  require("codediff.core.git").get_file_content(revision, git_root, relative, function(err, lines)
    vim.schedule(function()
      if set_scratch_lines(bufnr, err and {} or lines) then
        done()
      end
    end)
  end)
end

--- Put the modified side in the pane.
--- Unlike create, a virtual revision goes into a scratch buffer rather than a
--- codediff:// URI, so retargeting never races a pending BufReadCmd.
--- @param win number
--- @param session_config SessionConfig
--- @param is_virtual boolean
--- @return number bufnr
local function open_modified_for_update(win, session_config, is_virtual)
  if is_virtual then
    local mod_buf = new_scratch()
    vim.bo[mod_buf].modifiable = true
    vim.api.nvim_win_set_buf(win, mod_buf)
    local ft = vim.filetype.match({ filename = session_config.modified.absolute })
    if ft then
      vim.bo[mod_buf].filetype = ft
    end
    return mod_buf
  end

  local info = prepare_buffer(false, session_config.git_root, nil, session_config.modified)
  if info.needs_edit then
    return open_real_file(win, info.target)
  end
  show_real_file_buffer(win, info.bufnr)
  return info.bufnr
end

--- Fill the hidden original side. A real file is copied in synchronously; a
--- revision is fetched and lands through `done`.
--- @param orig_buf number
--- @param session_config SessionConfig
--- @param is_virtual boolean
--- @param done function Called when an async fetch lands
local function fill_original_for_update(orig_buf, session_config, is_virtual, done)
  if is_virtual then
    -- Retargeting can leave the original path empty (a file added in the
    -- modified revision), so fall back to the modified side's path.
    local relative = (session_config.original.relative ~= "" and session_config.original.relative) or session_config.modified.relative
    fetch_into_scratch(session_config.original_revision, session_config.git_root, relative, orig_buf, done)
    return
  end

  local orig_path = (session_config.original.absolute ~= "" and session_config.original.absolute) or session_config.modified.absolute
  if orig_path and orig_path ~= "" then
    local real_bufnr = vim.fn.bufadd(orig_path)
    vim.fn.bufload(real_bufnr)
    set_scratch_lines(orig_buf, vim.api.nvim_buf_get_lines(real_bufnr, 0, -1, false))
  end
end

--- Point the session at the newly computed diff and re-arm everything hanging
--- off it: refresh, keymaps, layout, and the window the user was in.
--- @param tabpage number
--- @param session_config SessionConfig
--- @param orig_buf number
--- @param mod_buf number
--- @param lines_diff table
--- @param saved_current_win number?
local function commit_update(tabpage, session_config, orig_buf, mod_buf, lines_diff, saved_current_win)
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

  -- Retargeting can move a session between a conflicted file and an ordinary
  -- one, so the merge flag follows the incoming config.
  lifecycle.update_merge(tabpage, session_config.conflict)

  local original_is_virtual = is_virtual_revision(session_config.original_revision)
  local modified_is_virtual = is_virtual_revision(session_config.modified_revision)

  local orig_buf = new_scratch()
  local mod_buf = open_modified_for_update(modified_win, session_config, modified_is_virtual)
  welcome_window.sync(modified_win)

  local should_auto_scroll = auto_scroll_to_first_hunk == true

  local render = function()
    if not vim.api.nvim_win_is_valid(modified_win) then
      return
    end
    if not vim.api.nvim_buf_is_valid(orig_buf) or not vim.api.nvim_buf_is_valid(mod_buf) then
      return
    end

    local lines_diff = compute_and_render_inline(
      mod_buf,
      orig_buf,
      vim.api.nvim_buf_get_lines(orig_buf, 0, -1, false),
      vim.api.nvim_buf_get_lines(mod_buf, 0, -1, false),
      original_is_virtual,
      modified_is_virtual,
      modified_win,
      should_auto_scroll
    )
    if lines_diff then
      commit_update(tabpage, session_config, orig_buf, mod_buf, lines_diff, saved_current_win)
    end
  end

  -- Each side reports whether it still owes content; the last one to land
  -- renders. Both may finish synchronously, hence the trailing check.
  -- Flags are set before the fetches start, never from their return values,
  -- so a callback can never be overwritten by a late assignment.
  local pending = { original = original_is_virtual, modified = modified_is_virtual }
  local function check_ready()
    if not pending.original and not pending.modified then
      render()
    end
  end

  fill_original_for_update(orig_buf, session_config, original_is_virtual, function()
    pending.original = false
    check_ready()
  end)

  if modified_is_virtual then
    fetch_into_scratch(session_config.modified_revision, session_config.git_root, session_config.modified.relative, mod_buf, function()
      pending.modified = false
      check_ready()
    end)
  end

  if not pending.original and not pending.modified then
    vim.schedule(render)
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
    file_bufnr = open_real_file(mod_win, file_path)
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
  view_keymaps.setup_all_keymaps(tabpage, orig_bufnr, mod_bufnr, session.panel ~= nil and session.panel.name == "explorer")
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
  view_keymaps.setup_all_keymaps(tabpage, empty_buf, load_bufnr, session.panel ~= nil and session.panel.name == "explorer")
  layout.arrange(tabpage)
  welcome_window.sync_later(mod_win)
end

return M
