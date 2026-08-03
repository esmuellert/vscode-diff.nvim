-- Scroll synchronization for aligned diff windows.
--
-- Replaces Neovim's built-in `scrollbind` for codediff's side-by-side and
-- 3-way (conflict/merge) views. Native `scrollbind` (the non-diff, generic
-- path) tracks position with a display-line count (`get_vtopline`) that becomes
-- discontinuous when a single virt_lines/diff filler block is taller than the
-- window (`w_topfill` is clamped). That discontinuity makes the bound window
-- oscillate between the correct position and a wrong one, redrawing the whole
-- pane each step -> visible flicker. Built-in `:diffthis` avoids this because it
-- syncs with `diff_set_topline` (a structural, diff-block mapping) instead.
--
-- This module ports that structural principle: it maps a window's scroll
-- position to a shared "virtual row" coordinate (each real line plus its filler
-- rows) and, on every scroll, sets the other windows to the same virtual row.
-- Because the mapping is structural, not display-line based, it has no clamp
-- discontinuity and produces zero flicker while scrolling through a full-screen
-- filler block, in either direction.
--
-- The alignment is derived from the fillers actually present in each window's
-- buffer (any `virt_lines` extmark), so the module stays decoupled from how the
-- diff is computed and automatically reflects fillers added by the renderer.
--
-- Assumes diff windows use `nowrap` (codediff does), so each real line occupies
-- exactly one screen row.

local api = vim.api

local M = {}

-- ---------------------------------------------------------------------------
-- Virtual-row mapping
-- ---------------------------------------------------------------------------

--- Build a sparse cumulative filler table for a buffer.
--- Reads every `virt_lines` extmark (all namespaces) so the mapping matches
--- Neovim's own fill accounting and covers alignment fillers plus any other
--- full-line virtual text.
--- @param bufnr integer
--- @return table ft { line_count, anchors (sorted 1-indexed), cum, total_fill }
local function build_fill_table(bufnr)
  local line_count = api.nvim_buf_line_count(bufnr)
  local marks = api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })

  local by_anchor = {}
  for _, m in ipairs(marks) do
    local details = m[4]
    local vlines = details and details.virt_lines
    if vlines and #vlines > 0 then
      local row = m[2] -- 0-indexed row the extmark is attached to
      -- `count` filler rows sit immediately ABOVE real line `anchor` (1-indexed).
      -- virt_lines_above => above line (row+1); otherwise below it => above (row+2).
      local anchor = details.virt_lines_above and (row + 1) or (row + 2)
      if anchor < 1 then
        anchor = 1
      elseif anchor > line_count + 1 then
        anchor = line_count + 1
      end
      by_anchor[anchor] = (by_anchor[anchor] or 0) + #vlines
    end
  end

  local anchors = {}
  for a in pairs(by_anchor) do
    anchors[#anchors + 1] = a
  end
  table.sort(anchors)

  local cum = {}
  local running = 0
  for i, a in ipairs(anchors) do
    running = running + by_anchor[a]
    cum[i] = running
  end

  return { line_count = line_count, anchors = anchors, cum = cum, total_fill = running }
end

--- Total filler rows whose anchor line is <= L. O(log fillers).
local function cumfill_le(ft, l)
  local anchors = ft.anchors
  local n = #anchors
  if n == 0 or l < anchors[1] then
    return 0
  end
  local lo, hi = 1, n
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if anchors[mid] <= l then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return ft.cum[lo]
end

--- 0-indexed virtual row of the text of real line L.
local function vrow_of_line(ft, l)
  return (l - 1) + cumfill_le(ft, l)
end

--- Map a window view {topline, topfill} to its top virtual row.
local function view_to_vrow(ft, topline, topfill)
  if topline < 1 then
    topline = 1
  elseif topline > ft.line_count then
    topline = ft.line_count
  end
  return vrow_of_line(ft, topline) - (topfill or 0)
end

--- Inverse: for a target virtual row, the (topline, topfill) that puts that
--- virtual row at the top of the window. topfill is NOT display-clamped here;
--- callers clamp against the actual window height.
local function vrow_to_view(ft, vrow)
  local lc = ft.line_count
  if vrow <= 0 then
    return 1, 0
  end
  if vrow_of_line(ft, lc) < vrow then
    -- Past the last line's text (into trailing fillers or EOF): pin to last line.
    return lc, 0
  end
  -- Smallest real line whose text vrow >= target.
  local lo, hi = 1, lc
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if vrow_of_line(ft, mid) >= vrow then
      hi = mid
    else
      lo = mid + 1
    end
  end
  local topline = lo
  local topfill = vrow_of_line(ft, topline) - vrow
  if topfill < 0 then
    topfill = 0
  end
  return topline, topfill
end

-- ---------------------------------------------------------------------------
-- Group
-- ---------------------------------------------------------------------------

local Group = {}
Group.__index = Group

local function view_fp(v)
  return string.format("%d,%d,%d", v.topline or 0, v.topfill or 0, v.leftcol or 0)
end

local function win_view(w)
  return api.nvim_win_call(w, vim.fn.winsaveview)
end

local function changed_windows(event, first)
  local changed = {}
  for key in pairs(event or {}) do
    local win = tonumber(key)
    if win then
      changed[win] = true
    end
  end
  local first_win = tonumber(first)
  if first_win then
    changed[first_win] = true
  end
  return next(changed) and changed or nil
end

function Group:_valid_wins()
  local out = {}
  for _, w in ipairs(self.wins) do
    if api.nvim_win_is_valid(w) then
      out[#out + 1] = w
    end
  end
  return out
end

function Group:_is_member(w)
  for _, m in ipairs(self.wins) do
    if m == w then
      return true
    end
  end
  return false
end

--- Rebuild the per-window fill tables from current buffer fillers. Call after
--- the diff/fillers are re-rendered.
function Group:refresh()
  self.ft = {}
  for _, w in ipairs(self:_valid_wins()) do
    self.ft[w] = build_fill_table(api.nvim_win_get_buf(w))
  end
  -- Fill tables changed; stored fingerprints are stale.
  self.expected = {}
  self.pending_echo = {}
end

--- Align every window other than `leader` to `leader`'s virtual-row position.
--- Mirrors horizontal scroll (leftcol). Uses a RELATIVE scroll by the computed
--- display-row delta so Neovim keeps its scroll optimization (hardware
--- `grid_scroll` + one drawn row), matching native scrollbind's rendering cost;
--- falls back to an absolute `winrestview` only if the relative scroll cannot
--- land exactly (buffer boundaries). `jump` forces the absolute path (used for
--- one-shot re-alignment where a large jump is expected).
function Group:_apply(leader, jump)
  local ftl = self.ft[leader]
  if not ftl then
    return
  end
  self.pending_echo[leader] = nil
  local lv = win_view(leader)
  local vrow = view_to_vrow(ftl, lv.topline, lv.topfill)
  self.vrow = vrow
  local leftcol = lv.leftcol or 0

  for _, w in ipairs(self:_valid_wins()) do
    if w ~= leader then
      local ft = self.ft[w]
      if ft then
        local target_tl, target_tf = vrow_to_view(ft, vrow)
        -- Clamp topfill to what the window can actually display (Neovim
        -- mishandles a stored topfill larger than the window height).
        local maxfill = api.nvim_win_get_height(w) - 1
        if maxfill < 0 then
          maxfill = 0
        end
        if target_tf > maxfill then
          target_tf = maxfill
        end

        local cur = win_view(w)
        local target_top_vrow = vrow_of_line(ft, target_tl) - target_tf
        local cur_top_vrow = vrow_of_line(ft, cur.topline) - (cur.topfill or 0)
        local delta = target_top_vrow - cur_top_vrow

        if delta ~= 0 then
          self.pending_echo[w] = true
          if not jump then
            -- Relative scroll (<C-e>/<C-y>) preserves the grid_scroll
            -- optimization so the follower is not fully repainted.
            local n = math.abs(delta)
            local key = delta > 0 and "\5" or "\25" -- <C-e> / <C-y>
            api.nvim_win_call(w, function()
              vim.cmd("normal! " .. n .. key)
            end)
          end
          -- Correct to the exact target if a jump was requested or the relative
          -- scroll fell short (e.g. near the top/bottom of the buffer).
          local after = win_view(w)
          if jump or after.topline ~= target_tl or (after.topfill or 0) ~= target_tf then
            api.nvim_win_call(w, function()
              vim.fn.winrestview({ topline = target_tl, topfill = target_tf })
            end)
          end
        end

        -- Mirror horizontal scroll (leftcol) without disturbing the vertical view.
        local fv = win_view(w)
        if (fv.leftcol or 0) ~= leftcol then
          self.pending_echo[w] = true
          api.nvim_win_call(w, function()
            local v = vim.fn.winsaveview()
            v.leftcol = leftcol
            vim.fn.winrestview(v)
          end)
        end

        self.expected[w] = view_fp(win_view(w))
      end
    end
  end
  self.expected[leader] = view_fp(lv)
end

--- Force a sync now, using `leader` (defaults to the current window if it is a
--- member, else the first window) as the source of truth. Uses the absolute
--- (jump) path since the windows may be far out of sync.
function Group:resync(leader)
  if leader == nil or not (leader and api.nvim_win_is_valid(leader) and self:_is_member(leader)) then
    local cur = api.nvim_get_current_win()
    leader = self:_is_member(cur) and cur or self:_valid_wins()[1]
  end
  if not leader then
    return
  end
  self.syncing = true
  local ok, err = pcall(function()
    self:_apply(leader, true)
  end)
  self.syncing = false
  if not ok then
    vim.notify_once("[codediff] scrollsync resync error: " .. tostring(err), vim.log.levels.DEBUG)
  end
end

--- Detect which member window the user actually scrolled by comparing each
--- window's current view against the fingerprint we last recorded. This catches
--- topfill-only scrolls and mouse scrolls of a non-focused window, and it
--- ignores the echo scroll events produced by our own winrestview (their
--- fingerprint matches `expected`).
function Group:_detect_leader(changed)
  local cur = api.nvim_get_current_win()
  local candidate
  for _, w in ipairs(self:_valid_wins()) do
    if not changed or changed[w] then
      local fp = view_fp(win_view(w))
      if fp ~= self.expected[w] then
        if w == cur then
          return w -- prefer the focused window when it moved
        end
        candidate = candidate or w
      end
    end
  end
  return candidate
end

function Group:_consume_pending_echoes(changed)
  if not changed then
    return
  end
  local current = api.nvim_get_current_win()
  for w in pairs(changed) do
    if w ~= current and self.pending_echo[w] then
      self.pending_echo[w] = nil
      self.expected[w] = view_fp(win_view(w))
    end
  end
end

function Group:_on_scroll(changed)
  if self.syncing then
    return
  end
  self:_consume_pending_echoes(changed)
  if self.paused then
    return
  end
  local leader = self:_detect_leader(changed)
  if not leader then
    return
  end
  self.syncing = true
  local ok, err = pcall(function()
    self:_apply(leader)
  end)
  self.syncing = false
  if not ok then
    vim.notify_once("[codediff] scrollsync error: " .. tostring(err), vim.log.levels.DEBUG)
  end
end

--- Temporarily stop syncing (e.g. while a feature imposes its own alignment).
function Group:pause()
  self.paused = true
end

--- Resume syncing and immediately re-align from the current window.
function Group:resume()
  self.paused = false
  self:resync()
end

--- Tear down: remove autocmds and mark inactive.
function Group:unbind()
  if self.augroup then
    pcall(api.nvim_del_augroup_by_id, self.augroup)
    self.augroup = nil
  end
  self.active = false
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Bind a set of windows so they scroll together, aligned by the fillers in
--- their buffers. Returns a group handle.
--- @param opts { wins: integer[] }
--- @return table group
function M.bind(opts)
  assert(opts and opts.wins and #opts.wins >= 2, "scrollsync.bind requires at least two windows")

  local self = setmetatable({
    wins = vim.deepcopy(opts.wins),
    ft = {},
    expected = {},
    pending_echo = {},
    syncing = false,
    paused = false,
    active = true,
    vrow = 0,
  }, Group)

  self:refresh()
  -- Seed fingerprints from the current views so the first real scroll is
  -- detected as a leader move (and our own echoes are not).
  for _, w in ipairs(self:_valid_wins()) do
    self.expected[w] = view_fp(win_view(w))
  end

  self.augroup = api.nvim_create_augroup("codediff_scrollsync_" .. tostring(self):gsub("%W", ""), { clear = true })
  api.nvim_create_autocmd("WinScrolled", {
    group = self.augroup,
    callback = function(args)
      if not self.active then
        return
      end
      -- Only react when a member window is involved.
      self:_on_scroll(changed_windows(vim.v.event, args.match))
    end,
  })
  -- A height change alters the topfill clamp; re-align to stay consistent.
  api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = self.augroup,
    callback = function()
      if not self.active or self.paused then
        return
      end
      self.syncing = true
      pcall(function()
        self:_apply(self:_detect_leader() or api.nvim_get_current_win(), true)
      end)
      self.syncing = false
    end,
  })
  -- Auto-teardown if any member window closes.
  api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    callback = function(args)
      local closed = tonumber(args.match)
      if closed and self:_is_member(closed) then
        self:unbind()
      end
    end,
  })

  return self
end

-- Exposed for tests.
M._internal = {
  build_fill_table = build_fill_table,
  changed_windows = changed_windows,
  vrow_of_line = vrow_of_line,
  view_to_vrow = view_to_vrow,
  vrow_to_view = vrow_to_view,
}

return M
