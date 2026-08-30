-- Unit tests for collapsed-state key disambiguation in explorer refresh.
-- Exercises state_key, collect_collapsed_state, and restore_collapsed_state
-- which are exposed via refresh._test for testing purposes.

local Tree = require("codediff.ui.lib.tree")
local refresh = require("codediff.ui.explorer.refresh")
local sk = refresh._test.state_key
local collect = refresh._test.collect_collapsed_state
local restore = refresh._test.restore_collapsed_state

-- Build a minimal Tree containing the given root nodes.
local function make_tree(root_nodes)
  return Tree({
    bufnr = vim.api.nvim_create_buf(false, true),
    nodes = root_nodes,
  })
end

-- Convenience: directory node with children.
local function dir_node(name, dir_path, group, children)
  return Tree.Node({
    text = name,
    data = { type = "directory", name = name, dir_path = dir_path, group = group },
  }, children or {})
end

-- Convenience: group node with children.
local function group_node(name, children)
  return Tree.Node({
    text = name,
    data = { type = "group", name = name },
  }, children or {})
end

describe("state_key", function()
  it("returns nil for nodes without data", function()
    local node = Tree.Node({ text = "x" })
    node.data = nil
    assert.is_nil(sk(node))
  end)

  it("returns nil for file nodes (no type field)", function()
    local node = Tree.Node({ text = "foo.lua", data = { path = "src/foo.lua" } })
    assert.is_nil(sk(node))
  end)

  it("keys group by name", function()
    local node = group_node("unstaged")
    assert.equal("group:unstaged", sk(node))
  end)

  it("keys directory by group + dir_path", function()
    local node = dir_node("internal", "src/internal", "unstaged")
    assert.equal("dir:unstaged:src/internal", sk(node))
  end)

  it("same dir_path in different groups gets different keys", function()
    local n1 = dir_node("internal", "src/internal", "unstaged")
    local n2 = dir_node("internal", "src/internal", "staged")
    assert.not_equal(sk(n1), sk(n2))
  end)

  it("same basename with different dir_path gets different keys", function()
    local n1 = dir_node("foo", "a/foo", "unstaged")
    local n2 = dir_node("foo", "b/foo", "unstaged")
    assert.not_equal(sk(n1), sk(n2))
  end)

  it("falls back to name when dir_path absent", function()
    local node = Tree.Node({
      text = "bar",
      data = { type = "directory", name = "bar", group = "unstaged" },
    })
    assert.equal("dir:unstaged:bar", sk(node))
  end)
end)

describe("collect_collapsed_state", function()
  it("returns empty table when nothing is collapsed", function()
    local d = dir_node("src", "src", "unstaged")
    d:expand()
    local grp = group_node("unstaged", { d })
    grp:expand()
    local tree = make_tree({ grp })
    local state = collect(tree)
    assert.same({}, state)
  end)

  it("records a collapsed group", function()
    local grp = group_node("unstaged")
    -- leave collapsed (default _expanded = false)
    local tree = make_tree({ grp })
    local state = collect(tree)
    assert.is_true(state["group:unstaged"])
  end)

  it("records a collapsed directory but not its expanded sibling", function()
    local d1 = dir_node("foo", "src/foo", "unstaged")
    local d2 = dir_node("bar", "src/bar", "unstaged")
    d1:collapse()
    d2:expand()

    local grp = group_node("unstaged", { d1, d2 })
    grp:expand()
    local tree = make_tree({ grp })

    local state = collect(tree)
    assert.is_true(state["dir:unstaged:src/foo"])
    assert.is_nil(state["dir:unstaged:src/bar"])
  end)

  it("does not confuse same dir_path in different groups", function()
    local d_unstaged = dir_node("foo", "src/foo", "unstaged")
    local d_staged = dir_node("foo", "src/foo", "staged")
    d_unstaged:collapse()
    d_staged:expand()

    local g1 = group_node("unstaged", { d_unstaged })
    local g2 = group_node("staged", { d_staged })
    g1:expand()
    g2:expand()
    local tree = make_tree({ g1, g2 })

    local state = collect(tree)
    assert.is_true(state["dir:unstaged:src/foo"])
    assert.is_nil(state["dir:staged:src/foo"])
  end)
end)

describe("restore_collapsed_state", function()
  it("collapses only the node whose key is in the state", function()
    local d1 = dir_node("foo", "src/foo", "unstaged")
    local d2 = dir_node("bar", "src/bar", "unstaged")
    d1:expand()
    d2:expand()

    local grp = group_node("unstaged", { d1, d2 })
    grp:expand()
    local tree = make_tree({ grp })

    local saved = { ["dir:unstaged:src/foo"] = true }
    restore(tree, saved, tree:get_nodes())

    assert.is_false(d1:is_expanded())
    assert.is_true(d2:is_expanded())
  end)

  it("does not bleed collapse across groups with same dir_path", function()
    local d_unstaged = dir_node("foo", "src/foo", "unstaged")
    local d_staged = dir_node("foo", "src/foo", "staged")
    d_unstaged:expand()
    d_staged:expand()

    local g1 = group_node("unstaged", { d_unstaged })
    local g2 = group_node("staged", { d_staged })
    g1:expand()
    g2:expand()
    local tree = make_tree({ g1, g2 })

    local saved = { ["dir:unstaged:src/foo"] = true }
    restore(tree, saved, tree:get_nodes())

    assert.is_false(d_unstaged:is_expanded())
    assert.is_true(d_staged:is_expanded())
  end)

  it("round-trips collect → restore correctly", function()
    local d1 = dir_node("foo", "src/foo", "unstaged")
    local d2 = dir_node("bar", "src/bar", "unstaged")
    d1:collapse()
    d2:expand()

    local grp = group_node("unstaged", { d1, d2 })
    grp:expand()
    local tree = make_tree({ grp })

    local saved = collect(tree)

    -- "Rebuild" tree: create fresh expanded nodes
    local d1b = dir_node("foo", "src/foo", "unstaged")
    local d2b = dir_node("bar", "src/bar", "unstaged")
    d1b:expand()
    d2b:expand()
    local grpb = group_node("unstaged", { d1b, d2b })
    grpb:expand()
    local tree2 = make_tree({ grpb })

    restore(tree2, saved, tree2:get_nodes())

    assert.is_false(d1b:is_expanded())
    assert.is_true(d2b:is_expanded())
  end)
end)
