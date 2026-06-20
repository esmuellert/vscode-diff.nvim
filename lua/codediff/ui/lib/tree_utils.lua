local M = {}

local devicons, mini_icons
local icons_provider_resolved = false

function M.find_foldable_node(node, tree)
  if node:is_foldable() then
    return node
  end

  if node._parent_id then
    local parent = tree:get_node(node._parent_id)
    if parent and parent:is_foldable() then
      return parent
    end
  end
  return nil
end

function M.find_foldable_at_cursor(tree)
  local node = tree:get_node()
  if not node then
    return nil
  end
  return M.find_foldable_node(node, tree)
end

function M.get_root_node(tree)
  local node = tree:get_node()
  if not node then
    return
  end

  local function find_root(n)
    if not n._parent_id then
      return n
    end
    local parent = tree:get_node(n._parent_id)
    if parent then
      return find_root(parent)
    else
      return n
    end
  end
  return find_root(node)
end

-- Setup all fold-related keymaps on a tree buffer.
-- @param opts table { tree, keymaps, bufnr }
function M.setup_fold_keymaps(opts)
  local tree = opts.tree
  local keymaps = opts.keymaps
  local bufnr = opts.bufnr

  local function update_tree_view(node)
    tree:render()
    local winid = vim.fn.bufwinid(bufnr)
    if node._line and winid ~= -1 then
      vim.api.nvim_win_set_cursor(winid, { node._line, 0 })
    end
  end

  local function fold_open()
    local node = M.find_foldable_at_cursor(tree)
    if not node then
      return
    end
    node:expand()
    update_tree_view(node)
  end

  local function fold_open_recursive()
    local node = M.find_foldable_at_cursor(tree)
    if not node then
      return
    end
    node:expand_recursively()
    update_tree_view(node)
  end

  local function fold_close()
    local node = M.find_foldable_at_cursor(tree)
    if not node then
      return
    end
    node:collapse()
    update_tree_view(node)
  end

  local function fold_close_recursive()
    local node = M.find_foldable_at_cursor(tree)
    if not node then
      return
    end
    node:collapse_recursively()
    update_tree_view(node)
  end

  local function fold_toggle()
    local node = M.find_foldable_at_cursor(tree)
    if not node then
      return
    end
    if node:is_expanded() then
      node:collapse()
    else
      node:expand()
    end
    update_tree_view(node)
  end

  local function fold_toggle_recursive()
    local node = M.find_foldable_at_cursor(tree)
    if not node then
      return
    end
    if node:is_expanded() then
      node:collapse_recursively()
    else
      node:expand_recursively()
    end
    update_tree_view(node)
  end

  local function fold_open_all()
    local root = M.get_root_node(tree)
    if not root then
      return
    end
    root:expand_recursively()
    update_tree_view(root)
  end

  local function fold_close_all()
    local root = M.get_root_node(tree)
    if not root then
      return
    end
    root:collapse_recursively()
    update_tree_view(root)
  end

  local fold_bindings = {
    { key = "fold_open", fn = fold_open, desc = "Open fold" },
    { key = "fold_open_recursive", fn = fold_open_recursive, desc = "Open fold recursively" },
    { key = "fold_close", fn = fold_close, desc = "Close fold" },
    { key = "fold_close_recursive", fn = fold_close_recursive, desc = "Close fold recursively" },
    { key = "fold_toggle", fn = fold_toggle, desc = "Toggle fold" },
    { key = "fold_toggle_recursive", fn = fold_toggle_recursive, desc = "Toggle fold recursively" },
    { key = "fold_open_all", fn = fold_open_all, desc = "Open all folds" },
    { key = "fold_close_all", fn = fold_close_all, desc = "Close all folds" },
  }
  local map_options = { noremap = true, silent = true, nowait = true }
  for _, binding in ipairs(fold_bindings) do
    local key = keymaps[binding.key]
    if key then
      vim.keymap.set("n", key, binding.fn, vim.tbl_extend("force", map_options, { buffer = bufnr, desc = binding.desc }))
    end
  end
end

-- File icons (basic fallback)
function M.get_file_icon(path)
  if not (devicons or mini_icons) then
    if icons_provider_resolved then
      return "", nil
    end

    local ok, mod = pcall(require, "nvim-web-devicons")
    if ok then
      devicons = mod
    else
      ok, mod = pcall(require, "mini.icons")
      if ok then
        mini_icons = mod
      end
    end

    icons_provider_resolved = true
  end

  local icon, color
  if devicons then
    icon, color = devicons.get_icon(path, nil, { default = true })
  elseif mini_icons then
    icon, color = mini_icons.get("file", path)
  end

  return icon or "", color
end

return M
