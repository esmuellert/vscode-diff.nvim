-- Session-level scroll-sync manager.
--
-- Owns one `codediff.scrollsync` group per diff tabpage and exposes the small
-- surface the view/lifecycle code needs. This replaces every use of Neovim's
-- native `scrollbind` in codediff (see codediff.scrollsync for why native
-- scrollbind flickers with tall virt_lines fillers).

local scrollsync = require("codediff.scrollsync")

local M = {}

-- tabpage -> { group, wins }
local groups = {}

local function same_wins(a, b)
  if #a ~= #b then
    return false
  end
  local set = {}
  for _, w in ipairs(a) do
    set[w] = true
  end
  for _, w in ipairs(b) do
    if not set[w] then
      return false
    end
  end
  return true
end

--- (Re)bind the diff windows for `tabpage` so they scroll together via the
--- structural virtual-row sync. Turns off native scrollbind defensively.
--- Reuses the existing group when the window set is unchanged.
--- @param tabpage integer
--- @param wins integer[]
--- @return table|nil group
function M.bind(tabpage, wins)
  local valid, seen = {}, {}
  for _, w in ipairs(wins or {}) do
    if w and vim.api.nvim_win_is_valid(w) and not seen[w] then
      seen[w] = true
      valid[#valid + 1] = w
      -- Ensure native scrollbind is off so it can't re-introduce the bug.
      pcall(function()
        vim.wo[w].scrollbind = false
      end)
    end
  end

  if #valid < 2 then
    M.teardown(tabpage)
    return nil
  end

  local existing = groups[tabpage]
  if existing and existing.group.active and same_wins(existing.wins, valid) then
    existing.group:refresh()
    return existing.group
  end

  if existing then
    existing.group:unbind()
  end

  local group = scrollsync.bind({ wins = valid })
  groups[tabpage] = { group = group, wins = valid }
  return group
end

--- @param tabpage integer
--- @return table|nil group
function M.get(tabpage)
  local entry = groups[tabpage]
  return entry and entry.group or nil
end

--- Force an immediate re-alignment (optionally from an explicit leader window).
function M.resync(tabpage, leader)
  local entry = groups[tabpage]
  if entry then
    entry.group:resync(leader)
  end
end

--- Rebuild the alignment from current buffer fillers, then re-align. Call after
--- the diff/fillers are re-rendered.
function M.refresh(tabpage, leader)
  local entry = groups[tabpage]
  if entry then
    entry.group:refresh()
    entry.group:resync(leader)
  end
end

--- Temporarily suspend syncing (e.g. while the move-alignment feature imposes
--- its own alignment).
function M.pause(tabpage)
  local entry = groups[tabpage]
  if entry then
    entry.group:pause()
  end
end

--- Resume syncing and re-align from the current window.
function M.resume(tabpage)
  local entry = groups[tabpage]
  if entry then
    entry.group:resume()
  end
end

--- Remove the group for a tabpage.
function M.teardown(tabpage)
  local entry = groups[tabpage]
  if entry then
    entry.group:unbind()
    groups[tabpage] = nil
  end
end

return M
