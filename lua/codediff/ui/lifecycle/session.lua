-- Session CRUD operations for diff views
-- Manages the active_diffs data structure
local M = {}

local config = require("codediff.config")
local virtual_file = require("codediff.core.virtual_file")
local accessors = require("codediff.ui.lifecycle.accessors")
local welcome_window = require("codediff.ui.view.welcome_window")

-- Track active diff sessions
-- Structure: {
--   tabpage_id = {
--     original_bufnr, modified_bufnr, original_win, modified_win,
--     mode = "standalone" | "explorer",
--     git_root = string?,
--     original = Path,
--     modified = Path,
--     original_revision = string?, -- nil | "WORKING" | "STAGED" | commit_hash
--     modified_revision = string?,
--     original_state, modified_state,
--     suspended = bool,
--     single_side = "original" | "modified" | nil,
--     stored_diff_result = table,
--     changedtick = { original = number, modified = number },
--     mtime = { original = number?, modified = number? },
--     -- Conflict mode result buffer (3-way merge)
--     result_bufnr = number?,  -- Real file buffer reset to BASE
--     result_win = number?,    -- Bottom window for result
--     conflict_files = table?, -- { [file_path] = true } tracks files opened in conflict mode
--   }
-- }
local active_diffs = {}

-- Get the active_diffs table (for other modules to access)
function M.get_active_diffs()
  return active_diffs
end

-- Check if a revision represents a virtual buffer
local function is_virtual_revision(revision)
  return revision ~= nil and revision ~= "WORKING"
end

-- Compute virtual URI from revision (not stored, computed on-demand)
local function compute_virtual_uri(git_root, revision, path)
  if not is_virtual_revision(revision) then
    return nil
  end
  return virtual_file.create_url(git_root, revision, path)
end

-- Expose compute_virtual_uri for other modules
M.compute_virtual_uri = compute_virtual_uri

function M.create_session(
  tabpage,
  mode,
  git_root,
  original,
  modified,
  original_revision,
  modified_revision,
  original_bufnr,
  modified_bufnr,
  original_win,
  modified_win,
  lines_diff,
  reapply_keymaps,
  exit_on_close
)
  local state = require("codediff.ui.lifecycle.state")
  -- Save buffer states
  local original_state = state.save_buffer_state(original_bufnr)
  local modified_state = state.save_buffer_state(modified_bufnr)

  -- Create complete session in one step
  active_diffs[tabpage] = {
    -- Mode & Git Context (immutable)
    mode = mode,
    git_root = git_root,
    original = original,
    modified = modified,
    original_revision = original_revision,
    modified_revision = modified_revision,

    -- Buffers & Windows
    original_bufnr = original_bufnr,
    modified_bufnr = modified_bufnr,
    original_win = original_win,
    modified_win = modified_win,
    original_state = original_state,
    modified_state = modified_state,

    -- Lifecycle state
    layout = "side-by-side",
    exit_on_close = exit_on_close == true,
    suspended = false,
    single_side = nil,
    stored_diff_result = lines_diff,
    changedtick = {
      original = vim.api.nvim_buf_get_changedtick(original_bufnr),
      modified = vim.api.nvim_buf_get_changedtick(modified_bufnr),
    },
    mtime = {
      original = state.get_file_mtime(original_bufnr),
      modified = state.get_file_mtime(modified_bufnr),
    },

    -- Explorer reference (only for explorer mode)
    explorer = nil,

    -- Conflict mode result buffer (3-way merge)
    result_bufnr = nil,
    result_win = nil,
    conflict_files = {}, -- Tracks files opened in conflict mode for unsaved warning
    reapply_keymaps = reapply_keymaps,
  }

  welcome_window.capture_session_profiles(active_diffs[tabpage])

  -- Mark windows with restore flag
  vim.w[original_win].codediff_restore = 1
  vim.w[modified_win].codediff_restore = 1

  -- Continuously enforce inlay hint settings via LspAttach (handles LazyVim re-enabling)
  if config.options.diff.disable_inlay_hints and vim.lsp.inlay_hint then
    vim.lsp.inlay_hint.enable(false, { bufnr = original_bufnr })
    vim.lsp.inlay_hint.enable(false, { bufnr = modified_bufnr })
  end

  -- Setup tab autocmds
  local tab_augroup = vim.api.nvim_create_augroup("codediff_lifecycle_tab_" .. tabpage, { clear = true })

  -- Re-disable inlay hints when LSP attaches (LazyVim/distributions may re-enable them)
  if config.options.diff.disable_inlay_hints then
    vim.api.nvim_create_autocmd("LspAttach", {
      group = tab_augroup,
      callback = function(ev)
        if not active_diffs[tabpage] then
          return
        end
        vim.schedule(function()
          if vim.api.nvim_get_current_tabpage() == tabpage then
            pcall(vim.lsp.inlay_hint.enable, false, { bufnr = ev.buf })
          end
        end)
      end,
    })
  end

  -- Force disable winbar to prevent alignment issues (except in conflict mode)
  local function sync_window_ui(sess, win)
    -- In conflict mode, preserve existing winbar titles (set by conflict_window.lua)
    if sess and sess.result_win and vim.api.nvim_win_is_valid(sess.result_win) then
      return
    end
    -- Normal diff mode: disable winbar
    if sess and sess.original_win and vim.api.nvim_win_is_valid(sess.original_win) then
      vim.wo[sess.original_win].winbar = ""
    end
    if sess and sess.modified_win and vim.api.nvim_win_is_valid(sess.modified_win) then
      vim.wo[sess.modified_win].winbar = ""
    end
  end

  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter", "WinEnter", "FileType" }, {
    group = tab_augroup,
    callback = function()
      local sess = active_diffs[tabpage]
      if not sess then
        return
      end
      local win = vim.api.nvim_get_current_win()
      if win == sess.original_win or win == sess.modified_win then
        sync_window_ui(sess, win)
        -- Re-apply critical window options that might get reset by ftplugins/autocmds
        vim.wo[win].wrap = false
        welcome_window.sync(win)
      end
    end,
  })

  vim.api.nvim_create_autocmd("TabLeave", {
    group = tab_augroup,
    callback = function()
      local current_tab = vim.api.nvim_get_current_tabpage()
      if current_tab == tabpage then
        accessors.clear_tab_keymaps(tabpage)
        state.suspend_diff(tabpage)
      end
    end,
  })

  vim.api.nvim_create_autocmd("TabEnter", {
    group = tab_augroup,
    callback = function()
      vim.schedule(function()
        local current_tab = vim.api.nvim_get_current_tabpage()
        if current_tab == tabpage and active_diffs[tabpage] then
          local sess = active_diffs[tabpage]
          if sess.reapply_keymaps then
            pcall(sess.reapply_keymaps)
          end
          state.resume_diff(tabpage)
        end
      end)
    end,
  })
end

return M
