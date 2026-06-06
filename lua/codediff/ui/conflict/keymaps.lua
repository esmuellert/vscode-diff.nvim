-- Keymap setup for conflict resolution
local M = {}

local lifecycle = require("codediff.ui.lifecycle")
local config = require("codediff.config")
local tracking = require("codediff.ui.conflict.tracking")
local actions = require("codediff.ui.conflict.actions")
local diffget = require("codediff.ui.conflict.diffget")
local navigation = require("codediff.ui.conflict.navigation")
local set_keymap = require("codediff.ui.lifecycle.accessors").set_keymap
local del_keymap = require("codediff.ui.lifecycle.accessors").del_keymap

--- Setup conflict keymaps for a session
--- @param tabpage number
function M.setup_keymaps(tabpage)
  local session = lifecycle.get_session(tabpage)
  if not session then
    return
  end

  local keymaps = config.options.keymaps.conflict or {}
  local view_keymaps = config.options.keymaps.view or {}

  -- Bind to incoming (left), current (right), AND result buffers
  local buffers = { session.original_bufnr, session.modified_bufnr, session.result_bufnr }

  local base_opts = { noremap = true, silent = true, nowait = true }

  for _, bufnr in ipairs(buffers) do
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      -- Unbind normal mode do/dp from view keymaps (they don't apply in merge conflict mode)
      if view_keymaps.diff_get then
        pcall(keymap_del, "n", view_keymaps.diff_get, { buffer = bufnr })
      end
      if view_keymaps.diff_put then
        pcall(keymap_del, "n", view_keymaps.diff_put, { buffer = bufnr })
      end

      -- Accept incoming
      if keymaps.accept_incoming then
        set_keymap(
          "n",
          keymaps.accept_incoming,
          tracking.make_repeatable(function()
            actions.accept_incoming(tabpage)
          end),
          vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Accept incoming change", expr = true })
        )
      end

      -- Accept current
      if keymaps.accept_current then
        set_keymap(
          "n",
          keymaps.accept_current,
          tracking.make_repeatable(function()
            actions.accept_current(tabpage)
          end),
          vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Accept current change", expr = true })
        )
      end

      -- Accept both
      if keymaps.accept_both then
        set_keymap(
          "n",
          keymaps.accept_both,
          tracking.make_repeatable(function()
            actions.accept_both(tabpage)
          end),
          vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Accept both changes", expr = true })
        )
      end

      -- Discard
      if keymaps.discard then
        set_keymap(
          "n",
          keymaps.discard,
          tracking.make_repeatable(function()
            actions.discard(tabpage)
          end),
          vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Discard changes (keep base)", expr = true })
        )
      end

      -- Accept ALL incoming
      if keymaps.accept_all_incoming then
        set_keymap("n", keymaps.accept_all_incoming, function()
          actions.accept_all_incoming(tabpage)
        end, vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Accept ALL incoming changes" }))
      end

      -- Accept ALL current
      if keymaps.accept_all_current then
        set_keymap("n", keymaps.accept_all_current, function()
          actions.accept_all_current(tabpage)
        end, vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Accept ALL current changes" }))
      end

      -- Accept ALL both
      if keymaps.accept_all_both then
        set_keymap("n", keymaps.accept_all_both, function()
          actions.accept_all_both(tabpage)
        end, vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Accept ALL both changes" }))
      end

      -- Discard ALL
      if keymaps.discard_all then
        set_keymap("n", keymaps.discard_all, function()
          actions.discard_all(tabpage)
        end, vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Discard ALL, reset to base" }))
      end

      -- Navigation
      if keymaps.next_conflict then
        set_keymap("n", keymaps.next_conflict, function()
          navigation.navigate_next_conflict(tabpage)
        end, vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Next conflict" }))
      end

      if keymaps.prev_conflict then
        set_keymap("n", keymaps.prev_conflict, function()
          navigation.navigate_prev_conflict(tabpage)
        end, vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Previous conflict" }))
      end

      -- Vimdiff-style diffget from incoming (2do) - only on result buffer
      if keymaps.diffget_incoming and bufnr == session.result_bufnr then
        set_keymap(
          "n",
          keymaps.diffget_incoming,
          tracking.make_repeatable(function()
            diffget.diffget_incoming(tabpage)
          end),
          vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Get hunk from incoming (2do)", expr = true })
        )
      end

      -- Vimdiff-style diffget from current (3do) - only on result buffer
      if keymaps.diffget_current and bufnr == session.result_bufnr then
        set_keymap(
          "n",
          keymaps.diffget_current,
          tracking.make_repeatable(function()
            diffget.diffget_current(tabpage)
          end),
          vim.tbl_extend("force", base_opts, { buffer = bufnr, desc = "Get hunk from current (3do)", expr = true })
        )
      end
    end
  end
end

return M
