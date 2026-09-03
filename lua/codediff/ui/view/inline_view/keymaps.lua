-- Keymap installation for inline diff sessions.
local M = {}

local lifecycle = require("codediff.ui.lifecycle")

function M.setup(tabpage, orig_buf, mod_buf)
  local view_keymaps = require("codediff.ui.view.keymaps")
  local session = lifecycle.get_session(tabpage)
  local is_explorer = session and session.panel ~= nil and session.panel.name == "explorer"
  view_keymaps.setup_all_keymaps(tabpage, orig_buf, mod_buf, is_explorer)
end

return M
