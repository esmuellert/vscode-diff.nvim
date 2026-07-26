-- Tests for codediff.scrollsync (structural scroll synchronization that
-- replaces native scrollbind) and the codediff.ui.scroll manager.

local scrollsync = require("codediff.scrollsync")
local internal = scrollsync._internal

local function make_win(lines, fillers)
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local ns = vim.api.nvim_create_namespace("scrollsync_test")
  for _, f in ipairs(fillers or {}) do
    local virt = {}
    for i = 1, f.count do
      virt[i] = { { "~fill~", "Comment" } }
    end
    -- f.after is 1-indexed "after this line"; extmark row is 0-indexed.
    vim.api.nvim_buf_set_extmark(buf, ns, f.after - 1, 0, { virt_lines = virt })
  end
  vim.wo.wrap = false
  return vim.api.nvim_get_current_win(), buf
end

local function view(win)
  return vim.api.nvim_win_call(win, vim.fn.winsaveview)
end

describe("scrollsync virtual-row mapping", function()
  it("builds a fill table and maps lines to virtual rows", function()
    local _, buf = make_win({ "a", "b", "c", "d", "e" }, { { after = 2, count = 3 } })
    local ft = internal.build_fill_table(buf)
    -- 3 filler rows sit above line 3 (after line 2).
    assert.equals(0, internal.vrow_of_line(ft, 1))
    assert.equals(1, internal.vrow_of_line(ft, 2))
    -- line 3 text is below its 3 fillers: 2 lines above + 3 fillers = vrow 5.
    assert.equals(5, internal.vrow_of_line(ft, 3))
    assert.equals(6, internal.vrow_of_line(ft, 4))
  end)

  it("vrow_to_view is the inverse of view_to_vrow", function()
    local _, buf = make_win({ "a", "b", "c", "d", "e", "f" }, { { after = 3, count = 4 } })
    local ft = internal.build_fill_table(buf)
    for _, tl in ipairs({ 1, 2, 3, 4, 5, 6 }) do
      for _, tf in ipairs({ 0, 1, 2 }) do
        -- topfill only meaningful up to the fill above tl; clamp to it
        local fill_above = internal.vrow_of_line(ft, tl) - internal.vrow_of_line(ft, tl - 1 >= 1 and tl - 1 or 1)
        if tl == 1 then
          fill_above = 0
        end
        local use_tf = math.min(tf, math.max(fill_above - (tl > 1 and 1 or 0), 0))
        local vrow = internal.view_to_vrow(ft, tl, use_tf)
        local back_tl, back_tf = internal.vrow_to_view(ft, vrow)
        assert.equals(vrow, internal.view_to_vrow(ft, back_tl, back_tf), string.format("roundtrip vrow mismatch tl=%d tf=%d", tl, use_tf))
      end
    end
  end)
end)

describe("scrollsync manager alignment", function()
  local scroll = require("codediff.ui.scroll")
  local tab

  before_each(function()
    vim.cmd("tabnew")
    tab = vim.api.nvim_get_current_tabpage()
    vim.o.lines = 16 -- small screen so a tall filler block clamps
  end)

  after_each(function()
    scroll.teardown(tab)
    pcall(vim.cmd, "tabclose")
  end)

  local function setup_pair()
    -- left = "delete" side (30 real lines + a 30-filler block replaced), right normal
    local left = {}
    for i = 1, 60 do
      left[i] = string.format("C%03d", i)
    end
    local win_left = make_win(left, { { after = 20, count = 30 } })
    vim.cmd("rightbelow vsplit")
    local right = {}
    for i = 1, 20 do
      right[i] = string.format("C%03d", i)
    end
    for k = 0, 29 do
      right[20 + k + 1] = string.format("I%03d", k)
    end
    for i = 21, 60 do
      right[#right + 1] = string.format("C%03d", i)
    end
    local win_right = make_win(right, {})
    return win_left, win_right
  end

  it("binds windows and keeps native scrollbind off", function()
    local wl, wr = setup_pair()
    scroll.bind(tab, { wl, wr })
    scroll.resync(tab, wr)
    assert.is_not_nil(scroll.get(tab))
    assert.is_false(vim.wo[wl].scrollbind)
    assert.is_false(vim.wo[wr].scrollbind)
  end)

  it("aligns the follower to the same virtual row on normal-content scroll", function()
    local wl, wr = setup_pair()
    scroll.bind(tab, { wl, wr })
    vim.api.nvim_set_current_win(wr)
    vim.cmd("normal! gg")
    scroll.resync(tab, wr)

    -- scroll right pane down through the shared top region (before the block)
    vim.api.nvim_win_call(wr, function()
      vim.fn.winrestview({ topline = 10, lnum = 10 })
    end)
    vim.api.nvim_exec_autocmds("WinScrolled", {})

    local group = scroll.get(tab)
    local ftl = group.ft[wl]
    local ftr = group.ft[wr]
    local vl = view(wl)
    local vr = view(wr)
    -- Neither is clamped here (top region has no fillers), so vrows are equal.
    assert.equals(
      internal.view_to_vrow(ftr, vr.topline, vr.topfill),
      internal.view_to_vrow(ftl, vl.topline, vl.topfill),
      "panes should share the same virtual row on normal-content scroll"
    )
  end)

  it("does not drift: scrolling down then up returns to the start", function()
    local wl, wr = setup_pair()
    scroll.bind(tab, { wl, wr })
    vim.api.nvim_set_current_win(wr)
    vim.cmd("normal! gg")
    scroll.resync(tab, wr)
    local start_l, start_r = view(wl), view(wr)

    for _ = 1, 25 do
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "nx", false)
      vim.api.nvim_exec_autocmds("WinScrolled", {})
    end
    for _ = 1, 25 do
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-y>", true, false, true), "nx", false)
      vim.api.nvim_exec_autocmds("WinScrolled", {})
    end

    local end_l, end_r = view(wl), view(wr)
    assert.equals(start_r.topline, end_r.topline, "leader topline restored")
    assert.equals(start_l.topline, end_l.topline, "follower topline restored")
    assert.equals(start_l.topfill, end_l.topfill, "follower topfill restored")
  end)

  it("does not oscillate through a full-screen filler block (the bug fix)", function()
    -- Filler block (30) is taller than the window, so it clamps. Native
    -- scrollbind oscillates the follower topline here; the structural sync must
    -- keep it monotonic (never jumping backwards to the top of the buffer).
    local wl, wr = setup_pair()
    scroll.bind(tab, { wl, wr })
    vim.api.nvim_set_current_win(wr)
    vim.cmd("normal! gg")
    scroll.resync(tab, wr)

    local toplines = {}
    for _ = 1, 40 do
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "nx", false)
      vim.api.nvim_exec_autocmds("WinScrolled", {})
      table.insert(toplines, view(wl).topline)
    end

    local prev = 0
    local max_backjump = 0
    for _, tl in ipairs(toplines) do
      if tl < prev then
        max_backjump = math.max(max_backjump, prev - tl)
      end
      prev = tl
    end
    -- Follower topline must be (weakly) monotonic while scrolling down; any
    -- large backwards jump would be the scrollbind oscillation.
    assert.is_true(max_backjump <= 1, "follower topline should not oscillate; max backward jump was " .. max_backjump)
  end)

  it("syncs three panes together (conflict/merge view)", function()
    -- Three equal-height aligned panes, each with a small filler block in a
    -- different place (blocks smaller than the window so nothing clamps). After
    -- any scroll, all three panes must sit at the same shared virtual row.
    local function forty()
      local t = {}
      for i = 1, 40 do
        t[i] = string.format("C%03d", i)
      end
      return t
    end
    local wa = make_win(forty(), { { after = 10, count = 5 } })
    vim.cmd("rightbelow vsplit")
    local wb = make_win(forty(), { { after = 20, count = 5 } })
    vim.cmd("rightbelow vsplit")
    local wc = make_win(forty(), { { after = 30, count = 5 } })

    scroll.bind(tab, { wa, wb, wc })
    assert.is_not_nil(scroll.get(tab))
    local group = scroll.get(tab)

    local function vrow(w)
      local v = view(w)
      return internal.view_to_vrow(group.ft[w], v.topline, v.topfill)
    end

    -- Drive each pane as the leader in turn; the other two must match its vrow.
    for _, leader in ipairs({ wc, wa, wb }) do
      vim.api.nvim_set_current_win(leader)
      vim.cmd("normal! gg")
      scroll.resync(tab, leader)
      for _ = 1, 20 do
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "nx", false)
        vim.api.nvim_exec_autocmds("WinScrolled", {})
        local va, vb, vc = vrow(wa), vrow(wb), vrow(wc)
        assert.equals(va, vb, "pane A and B must share the same virtual row")
        assert.equals(vb, vc, "pane B and C must share the same virtual row")
      end
    end
  end)
end)
