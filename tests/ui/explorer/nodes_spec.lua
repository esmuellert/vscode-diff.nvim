-- Test: Explorer node formatting (status symbol visibility, truncation)

local nodes = require("codediff.ui.explorer.nodes")
local Tree = require("codediff.ui.lib.tree")
local config = require("codediff.config")

-- Build a minimal file node as prepare_node expects it (list view mode).
local function make_file_node(path, status)
  return Tree.Node({
    text = path,
    data = {
      path = path,
      status = status,
      status_symbol = status,
      status_color = "CodeDiffStatusModified",
    },
  })
end

-- Find the segment carrying the status symbol's highlight group.
local function status_segment(line)
  for _, seg in ipairs(line._segments) do
    if seg.hl == "CodeDiffStatusModified" then
      return seg
    end
  end
  return nil
end

describe("explorer nodes: status symbol visibility", function()
  before_each(function()
    config.setup({ explorer = { view_mode = "list" } })
  end)

  it("keeps the status symbol visible when the filename alone is very long", function()
    local long_name = string.rep("a", 200) .. ".lua"
    local node = make_file_node(long_name, "M")

    local line = nodes.prepare_node(node, 40, nil, nil)

    local seg = status_segment(line)
    assert.is_not_nil(seg)
    assert.equals("M", seg.text)
  end)

  it("truncates an overly long filename with a single-cell ellipsis", function()
    local long_name = string.rep("b", 200) .. ".lua"
    local node = make_file_node(long_name, "M")

    local line = nodes.prepare_node(node, 40, nil, nil)
    local content = line:content()

    assert.truthy(content:find("…", 1, true))
    assert.is_false(content:find("%.%.%.", 1, false) ~= nil)
    assert.is_false(content:find(long_name, 1, true) ~= nil)
  end)

  it("does not truncate a short filename (no regression)", function()
    local node = make_file_node("short.lua", "M")

    local line = nodes.prepare_node(node, 40, nil, nil)
    local content = line:content()

    assert.truthy(content:find("short%.lua", 1, false))
    local seg = status_segment(line)
    assert.is_not_nil(seg)
    assert.equals("M", seg.text)
  end)

  it("leaves only a 1-cell gap between a maximally truncated name and the status column", function()
    local long_name = string.rep("c", 200) .. ".lua"
    local node = make_file_node(long_name, "M")

    local line = nodes.prepare_node(node, 40, nil, nil)
    local content = line:content()

    -- "…" + symbol_pad (default gap is 0) + "M" + margin.
    assert.truthy(content:find("… M $", 1, false))
  end)

  it("right-aligns single-char symbols within the status column (space before, not after)", function()
    local m_node = make_file_node("short.lua", "M")
    local untracked_node = Tree.Node({
      text = "short.lua",
      data = {
        path = "short.lua",
        status = "??",
        status_symbol = "??",
        status_color = "CodeDiffStatusUntracked",
      },
    })

    local m_line = nodes.prepare_node(m_node, 40, nil, nil)
    local untracked_line = nodes.prepare_node(untracked_node, 40, nil, nil)

    -- "??" fills its column; "M" gets a 1-cell pad to end at the same column.
    assert.equals(vim.fn.strdisplaywidth(m_line:content()), vim.fn.strdisplaywidth(untracked_line:content()))

    -- "M" needs 1 extra cell of padding that "??" (already full-width) doesn't.
    local function padding_width_before_status(line)
      local width = 0
      for _, seg in ipairs(line._segments) do
        if seg.hl == "CodeDiffStatusModified" or seg.hl == "CodeDiffStatusUntracked" then
          break
        end
        if seg.text:match("^%s+$") then
          width = width + vim.fn.strdisplaywidth(seg.text)
        end
      end
      return width
    end

    assert.equals(padding_width_before_status(untracked_line) + 1, padding_width_before_status(m_line))
  end)

  it("aligns the truncation point for \"??\" the same as single-char symbols", function()
    local long_name = string.rep("d", 200) .. ".lua"
    local modified_node = make_file_node(long_name, "M")
    local untracked_node = Tree.Node({
      text = long_name,
      data = {
        path = long_name,
        status = "??",
        status_symbol = "??",
        status_color = "CodeDiffStatusUntracked",
      },
    })

    local modified_line = nodes.prepare_node(modified_node, 40, nil, nil)
    local untracked_line = nodes.prepare_node(untracked_node, 40, nil, nil)

    assert.equals(modified_line._segments[1].text, untracked_line._segments[1].text)
  end)
end)
