-- Compatibility shims for Neovim API surface that changed across versions.
--
-- The plugin advertises Neovim >= 0.7. Several APIs we use were renamed or had
-- their signatures changed in 0.11, with the old form continuing to work but
-- emitting deprecation warnings (see issue #372). This module dispatches to the
-- modern signature on 0.11+ and the legacy signature on older versions.
local M = {}

local has_011 = vim.fn.has("nvim-0.11") == 1

--- vim.str_byteindex with UTF-16 indexing.
--- Neovim 0.11+: vim.str_byteindex(line, "utf-16", idx, strict_indexing)
--- Neovim <0.11: vim.str_byteindex(line, idx, true)
--- @param line string
--- @param idx integer 0-based UTF-16 character index
--- @return integer byte_idx 0-based byte index (or raises on out-of-range when strict)
function M.str_byteindex_utf16(line, idx)
  if has_011 then
    return vim.str_byteindex(line, "utf-16", idx, true)
  end
  return vim.str_byteindex(line, idx, true)
end

--- LSP client notify, dispatched as a method on 0.11+ and a function call on older versions.
--- Neovim 0.11+: client:notify(method, params) (function form deprecated)
--- Neovim <0.11: client.notify(method, params)
--- @param client table LSP client (from vim.lsp.get_clients())
--- @param method string LSP method name
--- @param params table|nil LSP params
function M.lsp_notify(client, method, params)
  if has_011 then
    return client:notify(method, params)
  end
  return client.notify(method, params)
end

--- LSP client request, same dispatch as lsp_notify.
--- @param client table
--- @param method string
--- @param params table|nil
--- @param handler function|nil
function M.lsp_request(client, method, params, handler)
  if has_011 then
    return client:request(method, params, handler)
  end
  return client.request(method, params, handler)
end

return M
