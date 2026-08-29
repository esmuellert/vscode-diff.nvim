-- Keymap ownership for diff sessions.
--
-- Translates a tabpage into that session's keymap registry, so callers only
-- need the tabpage they already have. Holds no mapping logic of its own: every
-- claim and release is delegated to codediff.keymap.
local M = {}

-- Eagerly loaded: these run from scheduled callbacks that may execute after the
-- CWD changed, where a first-time require would fail.
local keymap = require("codediff.keymap")

-- Lazy require to avoid circular dependency: init -> session -> accessors -> session
local function get_active_diffs()
  return require("codediff.ui.lifecycle.session").get_active_diffs()
end

--- Registry that owns every mapping this session installs.
--- Created lazily so sessions built by older call paths still work.
--- @param sess table
--- @return table|nil registry
local function registry_for(sess)
  if not sess then
    return nil
  end
  if not sess.keymaps then
    sess.keymaps = keymap.new("codediff-session")
  end
  return sess.keymaps
end

--- Buffers that currently belong to a session, by role.
--- @param sess table
--- @return table<string, number> roles
local function session_buffers(sess)
  local buffers = {}
  if sess.original_bufnr and vim.api.nvim_buf_is_valid(sess.original_bufnr) then
    buffers.original = sess.original_bufnr
  end
  if sess.modified_bufnr and vim.api.nvim_buf_is_valid(sess.modified_bufnr) then
    buffers.modified = sess.modified_bufnr
  end
  local panel_view = sess.panel and sess.panel.view
  if panel_view and panel_view.bufnr and vim.api.nvim_buf_is_valid(panel_view.bufnr) then
    buffers.panel = panel_view.bufnr
  end
  if sess.result_bufnr and vim.api.nvim_buf_is_valid(sess.result_bufnr) then
    buffers.result = sess.result_bufnr
  end
  return buffers
end

--- Set a keymap on all buffers in the diff tab (both diff buffers + explorer + result)
--- This is the unified API for setting tab-wide keymaps
--- @param tabpage number Tab page ID
--- @param mode string|string[] Keymap mode ('n', 'v', etc.)
--- @param lhs string Left-hand side of the keymap
--- @param rhs function|string Right-hand side (callback or command)
--- @param opts? table Optional keymap options (will be merged with buffer-local defaults)
--- @return boolean success True if keymaps were set
function M.set_tab_keymap(tabpage, mode, lhs, rhs, opts)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    return false
  end

  local reg = registry_for(sess)
  local base_opts = { noremap = true, silent = true, nowait = true }
  local merged = vim.tbl_extend("force", base_opts, opts or {})

  for _, bufnr in pairs(session_buffers(sess)) do
    reg:claim(bufnr, mode, lhs, rhs, merged)
  end

  return true
end

--- Set a keymap on one specific buffer, owned by the session's registry.
--- Used for mappings that are scoped to a single role (hunk operations and the
--- hunk textobject on diff panes, conflict actions, panel actions).
--- @param tabpage number
--- @param bufnr number
--- @param mode string|string[]
--- @param lhs string|false|nil Configured binding; false/nil silently disables
--- @param rhs function|string
--- @param opts? table Forwarded verbatim to vim.keymap.set
--- @param meta? table { suspendable = boolean, priority = integer }
--- @return boolean success
function M.set_buf_keymap(tabpage, bufnr, mode, lhs, rhs, opts, meta)
  local active_diffs = get_active_diffs()
  local sess = active_diffs[tabpage]
  if not sess then
    -- No session to own the mapping (a panel built outside a diff tab, for
    -- example). Fall back to a plain buffer-local mapping so behavior matches
    -- the pre-registry implementation rather than silently binding nothing.
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
      return false
    end
    local bound = false
    for _, resolved in ipairs(keymap.key_list(lhs)) do
      local ok = pcall(vim.keymap.set, mode, resolved, rhs, vim.tbl_extend("force", opts or {}, { buffer = bufnr }))
      bound = bound or ok
    end
    return bound
  end
  return registry_for(sess):claim(bufnr, mode, lhs, rhs, opts, meta)
end

--- True when the session currently owns a mapping for `lhs`.
--- Used by the help popup so it can describe what is really bound rather than
--- a hand-maintained list that drifts.
--- @param tabpage number
--- @param lhs string|false|nil
--- @param mode string|nil Restrict to one mode; any mode when omitted
--- @param bufnr number|nil Restrict to one buffer; any session buffer when omitted
--- @return boolean
function M.owns_keymap(tabpage, lhs, mode, bufnr)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return false
  end
  return sess.keymaps:owns(lhs, mode, bufnr)
end

--- Keys the session owns that are expected to appear in the help popup.
--- @param tabpage number
--- @return table<string, boolean> canonical lhs -> true
function M.documented_keymaps(tabpage)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return {}
  end
  return sess.keymaps:documented_keys()
end

--- Begin a keymap setup pass for `scope` on this session.
--- Claims made until end_keymap_scope are tagged; anything in the scope the
--- pass does not re-claim is released, so a shape change (layout toggle,
--- leaving conflict mode, reconfiguration) cannot leave stale mappings behind.
--- @param tabpage number
--- @param scope string
function M.begin_keymap_scope(tabpage, scope)
  local sess = get_active_diffs()[tabpage]
  if sess then
    registry_for(sess):begin_scope(scope)
  end
end

--- Finish a keymap setup pass, releasing claims it did not renew.
--- @param tabpage number
--- @param scope string|nil Names the pass to close; defaults to the innermost
function M.end_keymap_scope(tabpage, scope)
  local sess = get_active_diffs()[tabpage]
  if sess and sess.keymaps then
    sess.keymaps:end_scope(scope)
  end
end

--- Release every mapping belonging to `scope`.
--- @param tabpage number
--- @param scope string
function M.release_keymap_scope(tabpage, scope)
  local sess = get_active_diffs()[tabpage]
  if sess and sess.keymaps then
    sess.keymaps:release_scope(scope)
  end
end

--- Release a specific mapping the session installed on a buffer.
--- @param tabpage number
--- @param bufnr number
--- @param mode string|string[]
--- @param lhs string|false|nil
function M.del_buf_keymap(tabpage, bufnr, mode, lhs)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    local resolved = keymap.resolve(lhs)
    if resolved and bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      for _, m in ipairs(type(mode) == "table" and mode or { mode }) do
        pcall(vim.keymap.del, m, resolved, { buffer = bufnr })
      end
    end
    return
  end
  sess.keymaps:release(bufnr, mode, lhs)
end

--- Release every mapping the session installed on a buffer that is leaving it.
--- @param tabpage number
--- @param bufnr number
function M.detach_keymap_buffer(tabpage, bufnr)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return
  end
  sess.keymaps:detach_buffer(bufnr)
end

--- Suspend the session's mappings on borrowed (real file) buffers.
--- Called on TabLeave so codediff keys do not appear on those files in other
--- tabs. Panel mappings are registered as non-suspendable and stay installed.
--- @param tabpage number
function M.clear_tab_keymaps(tabpage)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return
  end
  sess.keymaps:suspend()
end

--- Reinstall mappings suspended by clear_tab_keymaps.
--- @param tabpage number
function M.restore_tab_keymaps(tabpage)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return
  end
  sess.keymaps:resume()
end

--- Release every mapping the session installed, handing each key back to
--- whatever owned it before codediff. Idempotent.
--- @param tabpage number
function M.dispose_keymaps(tabpage)
  local sess = get_active_diffs()[tabpage]
  if not sess or not sess.keymaps then
    return
  end
  sess.keymaps:dispose()
  sess.keymaps = nil
end

return M
