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

  it("collects changed window IDs from WinScrolled data", function()
    assert.same({ [12] = true, [13] = true, [14] = true }, internal.changed_windows({ all = {}, ["12"] = {}, [13] = {} }, "14"))
    assert.is_nil(internal.changed_windows({}, ""))
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

  local function setup_pair(insert_count)
    insert_count = insert_count or 30
    -- left = "delete" side (30 real lines + a 30-filler block replaced), right normal
    local left = {}
    for i = 1, 60 do
      left[i] = string.format("C%03d", i)
    end
    local win_left = make_win(left, { { after = 20, count = insert_count } })
    vim.cmd("rightbelow vsplit")
    local right = {}
    for i = 1, 20 do
      right[i] = string.format("C%03d", i)
    end
    for k = 0, insert_count - 1 do
      right[20 + k + 1] = string.format("I%03d", k)
    end
    for i = 21, 60 do
      right[#right + 1] = string.format("C%03d", i)
    end
    local win_right = make_win(right, {})
    return win_left, win_right
  end

  local function set_view(win, topline, cursor_line)
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ topline = topline, lnum = cursor_line })
    end)
  end

  local function fire_win_scrolled(group, win)
    group:_on_scroll({ [win] = true })
  end

  local function setup_pending_follower_echo()
    local follower, leader = setup_pair()
    local group = scroll.bind(tab, { follower, leader })
    vim.api.nvim_set_current_win(leader)
    set_view(leader, 35, 40)
    group:resync(leader)
    group.pending_echo[follower] = true
    return { group = group, leader = leader, follower = follower }
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

  it("waits for the pending follower's own WinScrolled event", function()
    local scenario = setup_pending_follower_echo()

    fire_win_scrolled(scenario.group, scenario.leader)
    assert.is_true(
      scenario.group.pending_echo[scenario.follower],
      "another window must not consume the follower's echo"
    )

    fire_win_scrolled(scenario.group, scenario.follower)
    assert.is_nil(
      scenario.group.pending_echo[scenario.follower],
      "the follower's own event must consume its echo"
    )
  end)

  it("keeps the active leader fixed when a follower redraw corrects its view", function()
    local scenario = setup_pending_follower_echo()
    local leader_before = view(scenario.leader)
    set_view(scenario.follower, 10, 20)

    fire_win_scrolled(scenario.group, scenario.follower)

    local leader_after = view(scenario.leader)
    assert.equals(leader_before.topline, leader_after.topline, "follower redraw must not move the leader")
    assert.equals(
      leader_before.topfill,
      leader_after.topfill,
      "follower redraw must not change the leader's filler offset"
    )
  end)

  it("keeps the follower on the aligned baseline after leaving a full-screen filler", function()
    local follower, leader = setup_pair(214)
    local group = scroll.bind(tab, { follower, leader })
    vim.api.nvim_set_current_win(leader)
    vim.wo[follower].scrolloff = 8
    set_view(follower, 21, 21)
    set_view(leader, 21, 25)
    group:resync(leader)
    fire_win_scrolled(group, follower)

    set_view(leader, 20, 24)
    fire_win_scrolled(group, leader)
    local follower_view = view(follower)
    local follower_cursor = vim.api.nvim_win_get_cursor(follower)[1]

    assert.is_true(follower_cursor >= follower_view.topline, "the follower cursor must remain in the aligned view")
    assert.equals(0, vim.wo[follower].scrolloff, "the follower view must remain stable until its redraw")
    fire_win_scrolled(group, follower)
    vim.cmd("redraw")
    assert.equals(8, vim.wo[follower].scrolloff, "the follower's scrolloff must be restored after its redraw")
    assert.equals(20, view(follower).topline, "the follower must not flash unrelated baseline text")
  end)

  it("treats a later non-focused follower scroll as user input", function()
    local scenario = setup_pending_follower_echo()
    fire_win_scrolled(scenario.group, scenario.follower)
    assert.is_nil(
      scenario.group.pending_echo[scenario.follower],
      "the programmatic echo must be consumed first"
    )
    local leader_before = view(scenario.leader)
    set_view(scenario.follower, 10, 20)

    fire_win_scrolled(scenario.group, scenario.follower)

    local leader_after = view(scenario.leader)
    assert.not_equal(
      leader_before.topline,
      leader_after.topline,
      "later user scrolling in the follower must move the leader"
    )
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

-- Regression (#254): duplicating a diff window (`<C-w>s`, optionally followed by
-- `<C-w>T` to move it to a new tab) must not carry the scroll mirroring with it.
-- Native `scrollbind` is a window-local option that `:split` copies, so a clone
-- of a bound pane stayed scroll-bound to its sibling. The structural sync only
-- ever drives the explicit window IDs it was given and keeps every bindable
-- window option off, so clones are always independent.
describe("scrollsync window duplication (#254)", function()
  local scroll = require("codediff.ui.scroll")
  local tab

  before_each(function()
    vim.cmd("tabnew")
    tab = vim.api.nvim_get_current_tabpage()
    vim.o.lines = 24
  end)

  after_each(function()
    scroll.teardown(tab)
    while vim.fn.tabpagenr("$") > 1 do
      pcall(vim.cmd, "tabclose!")
    end
  end)

  -- Two bound panes over the same long content, no fillers needed: the bug is
  -- about option inheritance, not alignment.
  local function bound_pair()
    local lines = {}
    for i = 1, 200 do
      lines[i] = string.format("line %03d", i)
    end
    local left = make_win(lines, {})
    vim.cmd("rightbelow vsplit")
    local right = make_win(lines, {})
    scroll.bind(tab, { left, right })
    scroll.resync(tab, right)
    return left, right
  end

  local function topline(win)
    return vim.api.nvim_win_call(win, function()
      return vim.fn.line("w0")
    end)
  end

  local function scroll_down(win, count)
    vim.api.nvim_set_current_win(win)
    for _ = 1, count do
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "nx", false)
    end
    -- Headless has no UI, so WinScrolled does not fire on its own.
    vim.api.nvim_exec_autocmds("WinScrolled", {})
  end

  it("leaves no inheritable scroll-binding option on the diff windows", function()
    local wl, wr = bound_pair()
    for _, w in ipairs({ wl, wr }) do
      -- Every one of these is copied by :split and would mirror scrolling.
      assert.is_false(vim.wo[w].scrollbind, "scrollbind must stay off on diff windows")
      assert.is_false(vim.wo[w].cursorbind, "cursorbind must stay off on diff windows")
      assert.is_false(vim.wo[w].diff, "diff must stay off on diff windows")
    end
  end)

  it("does not scroll-mirror a window split off a diff pane", function()
    local wl, wr = bound_pair()

    vim.api.nvim_set_current_win(wr)
    vim.cmd("split")
    local clone = vim.api.nvim_get_current_win()
    assert.are_not.equal(wr, clone, "split should create a new window")
    assert.is_false(vim.wo[clone].scrollbind, "the split window must not inherit scrollbind")

    local group = scroll.get(tab)
    assert.is_not_nil(group, "the diff panes should still be bound")
    for _, w in ipairs(group.wins) do
      assert.are_not.equal(clone, w, "the split window must not join the scroll-sync group")
    end

    local clone_top = topline(clone)
    scroll_down(wr, 30)

    assert.is_true(topline(wr) > 1, "the diff pane should have scrolled")
    assert.is_true(topline(wl) > 1, "the other diff pane should follow (sync is live)")
    assert.are.equal(clone_top, topline(clone), "the split window must stay put")
  end)

  it("does not scroll-mirror the panes of a new tab opened with <C-w>s<C-w>T", function()
    local _, wr = bound_pair()

    -- The exact sequence from the issue: split the diff pane, then move that
    -- split to its own tab.
    vim.api.nvim_set_current_win(wr)
    vim.cmd("wincmd s")
    local moved = vim.api.nvim_get_current_win()
    -- The intermediate split is where the mirroring used to leak in: `wincmd T`
    -- itself resets scrollbind, so the clone must already be clean here.
    assert.is_false(vim.wo[moved].scrollbind, "the intermediate split must not inherit scrollbind")
    vim.cmd("wincmd T")
    local new_tab = vim.api.nvim_get_current_tabpage()
    assert.are_not.equal(tab, new_tab, "wincmd T should move the window to a new tab")

    -- Splitting inside the new tab must give two fully independent windows.
    vim.cmd("split")
    local wins = vim.api.nvim_tabpage_list_wins(new_tab)
    assert.are.equal(2, #wins, "the new tab should have two windows")
    for _, w in ipairs(wins) do
      assert.is_false(vim.wo[w].scrollbind, "windows in the new tab must not have scrollbind")
    end

    local other = wins[1]
    local driver = wins[2]
    local other_top = topline(other)
    scroll_down(driver, 30)

    assert.is_true(topline(driver) > 1, "the driven window should have scrolled")
    assert.are.equal(other_top, topline(other), "the sibling in the new tab must stay put")
  end)
end)
