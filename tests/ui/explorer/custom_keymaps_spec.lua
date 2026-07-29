local Tree = require("codediff.ui.lib.tree")
local Line = require("codediff.ui.lib.line")
local config = require("codediff.config")
local keymaps = require("codediff.ui.explorer.keymaps")
local nodes = require("codediff.ui.explorer.nodes")
local refresh = require("codediff.ui.explorer.refresh")
local explorer_tree = require("codediff.ui.explorer.tree")

local original_refresh = refresh.refresh

local reset_config = function()
  config.options = vim.deepcopy(config.defaults)
  config.options.explorer.view_mode = "tree"
  config.options.explorer.flatten_dirs = false
end

local create_explorer = function(prepare_node)
  local previous_bufnr = vim.api.nvim_get_current_buf()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, bufnr)
  local files = {
    {
      path = "src/renamed.lua",
      old_path = "src/old.lua",
      status = "M",
      line_stats = { insertions = 5, deletions = 2, binary = false },
    },
    { path = "src/new.lua", status = "A", line_stats = { insertions = 3, deletions = 1, binary = false } },
  }
  local roots = explorer_tree.create_tree_data({ unstaged = files, staged = {}, conflicts = {} }, "/repo", nil, false, {
    unstaged = true,
    staged = false,
  })
  local tree = Tree({
    bufnr = bufnr,
    nodes = roots,
    prepare_node = prepare_node and function(node)
      local line = Line()
      line:append(prepare_node(node), "Normal")
      return line
    end,
  })
  roots[1]:expand()
  roots[1]._children[1]:expand()
  tree:render()
  return {
    previous_bufnr = previous_bufnr,
    root = roots[1],
    directory = roots[1]._children[1],
    file = roots[1]._children[1]._children[2],
    explorer = {
      bufnr = bufnr,
      winid = vim.api.nvim_get_current_win(),
      tabpage = vim.api.nvim_get_current_tabpage(),
      split = { bufnr = bufnr },
      tree = tree,
    },
  }
end

local cleanup_explorer = function(fixture)
  if vim.api.nvim_buf_is_valid(fixture.previous_bufnr) then
    vim.api.nvim_win_set_buf(0, fixture.previous_bufnr)
  end
  if vim.api.nvim_buf_is_valid(fixture.explorer.bufnr) then
    vim.api.nvim_buf_delete(fixture.explorer.bufnr, { force = true })
  end
end

describe("Explorer custom keymaps", function()
  before_each(function()
    reset_config()
    refresh.refresh = original_refresh
  end)

  after_each(function()
    refresh.refresh = original_refresh
    config.options = vim.deepcopy(config.defaults)
  end)

  it("exposes stable file, directory, and group entries", function()
    local fixture = create_explorer()

    assert.same({
      kind = "file",
      path = "src/renamed.lua",
      old_path = "src/old.lua",
      group = "unstaged",
      status = "M",
    }, nodes.get_entry(fixture.file))
    assert.same({
      kind = "directory",
      name = "src",
      path = "src",
      group = "unstaged",
      files = {
        { path = "src/renamed.lua", old_path = "src/old.lua", group = "unstaged", status = "M" },
        { path = "src/new.lua", group = "unstaged", status = "A" },
      },
    }, nodes.get_entry(fixture.directory))
    assert.same({
      kind = "group",
      name = "unstaged",
      group = "unstaged",
      files = {
        { path = "src/renamed.lua", old_path = "src/old.lua", group = "unstaged", status = "M" },
        { path = "src/new.lua", group = "unstaged", status = "A" },
      },
    }, nodes.get_entry(fixture.root))

    cleanup_explorer(fixture)
  end)

  it("includes line stats in callback entries when enabled", function()
    config.options.explorer.line_stats.enabled = true
    local fixture = create_explorer()
    local totals = {
      files_changed = 2,
      insertions = 8,
      deletions = 3,
      binary_files = 0,
      unavailable_files = 0,
    }

    assert.same({ insertions = 5, deletions = 2, binary = false }, nodes.get_entry(fixture.file).stats)
    assert.same(totals, nodes.get_entry(fixture.directory).stats)
    assert.same(totals, nodes.get_entry(fixture.root).stats)
    assert.same({
      {
        path = "src/renamed.lua",
        old_path = "src/old.lua",
        group = "unstaged",
        status = "M",
        stats = { insertions = 5, deletions = 2, binary = false },
      },
      {
        path = "src/new.lua",
        group = "unstaged",
        status = "A",
        stats = { insertions = 3, deletions = 1, binary = false },
      },
    }, nodes.get_entry(fixture.directory).files)

    cleanup_explorer(fixture)
  end)

  it("uses custom descriptions and lets custom mappings override built-ins", function()
    local fixture = create_explorer()
    local calls = 0
    local refresh_calls = 0
    refresh.refresh = function()
      refresh_calls = refresh_calls + 1
    end
    config.options.keymaps.explorer.custom = {
      {
        key = "R",
        desc = "Custom refresh action",
        callback = function()
          calls = calls + 1
        end,
      },
    }

    keymaps.setup(fixture.explorer)
    local mapping = vim.fn.maparg("R", "n", false, true)
    mapping.callback()

    assert.equals("Custom refresh action", mapping.desc)
    assert.equals(1, mapping.buffer)
    assert.equals(1, calls)
    assert.equals(0, refresh_calls)
    cleanup_explorer(fixture)
  end)

  it("redraws the existing tree without changing identity, folds, or selection", function()
    local reviewed = false
    local fixture = create_explorer(function(node)
      return node.text .. (reviewed and " reviewed" or "")
    end)
    fixture.directory:collapse()
    fixture.explorer.tree:render()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local root_id = fixture.root:get_id()
    local directory_id = fixture.directory:get_id()
    config.options.keymaps.explorer.custom = {
      {
        key = "m",
        desc = "Mark reviewed",
        callback = function(ctx)
          reviewed = true
          ctx.redraw()
        end,
      },
    }

    keymaps.setup(fixture.explorer)
    vim.fn.maparg("m", "n", false, true).callback()

    assert.equals(fixture.root, fixture.explorer.tree:get_nodes()[1])
    assert.equals(fixture.root, fixture.explorer.tree:get_node(root_id))
    assert.equals(fixture.directory, fixture.explorer.tree:get_node(directory_id))
    assert.is_true(fixture.root:is_expanded())
    assert.is_false(fixture.directory:is_expanded())
    assert.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
    assert.equals("src reviewed", vim.api.nvim_buf_get_lines(fixture.explorer.bufnr, 1, 2, false)[1])
    cleanup_explorer(fixture)
  end)

  it("forwards refresh and becomes safe after the explorer closes", function()
    local fixture = create_explorer()
    local context
    local refresh_calls = 0
    local render_calls = 0
    config.options.keymaps.explorer.custom = {
      {
        key = "x",
        desc = "Capture context",
        callback = function(ctx)
          context = ctx
        end,
      },
    }
    refresh.refresh = function(explorer)
      assert.equals(fixture.explorer, explorer)
      refresh_calls = refresh_calls + 1
    end

    keymaps.setup(fixture.explorer)
    vim.fn.maparg("x", "n", false, true).callback()
    context.refresh()
    assert.equals(1, refresh_calls)

    fixture.explorer.tree.render = function()
      render_calls = render_calls + 1
    end
    fixture.explorer.tabpage = 999999
    assert.has_no.errors(context.redraw)
    assert.has_no.errors(context.refresh)
    assert.equals(0, render_calls)
    assert.equals(1, refresh_calls)

    fixture.explorer.tabpage = vim.api.nvim_get_current_tabpage()
    cleanup_explorer(fixture)
    assert.has_no.errors(context.redraw)
    assert.has_no.errors(context.refresh)
    assert.equals(0, render_calls)
    assert.equals(1, refresh_calls)
  end)
end)
