local M = {}

local welcome = require("codediff.ui.welcome")

local option_names = {
  "number",
  "relativenumber",
  "foldcolumn",
}

local welcome_opts = {
  number = false,
  relativenumber = false,
  foldcolumn = "0",
}

local function is_valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function read_window_opts(winid)
  local opts = {}
  for _, name in ipairs(option_names) do
    opts[name] = vim.wo[winid][name]
  end
  return opts
end

local function apply_opts(winid, opts)
  for name, value in pairs(opts) do
    vim.wo[winid][name] = value
  end
end

local function get_session_for_window(winid)
  local active_diffs = require("codediff.ui.lifecycle.session").get_active_diffs()
  for _, sess in pairs(active_diffs) do
    if sess.original_win == winid then
      return sess, "original"
    end
    if sess.modified_win == winid then
      return sess, "modified"
    end
  end
  return nil, nil
end

function M.capture_session_profiles(sess)
  if not sess then
    return
  end

  sess.window_profiles = sess.window_profiles or {}
  if is_valid_window(sess.original_win) and not sess.window_profiles.original then
    sess.window_profiles.original = read_window_opts(sess.original_win)
  end
  if is_valid_window(sess.modified_win) and not sess.window_profiles.modified then
    sess.window_profiles.modified = read_window_opts(sess.modified_win)
  end
end

function M.apply(winid)
  if not is_valid_window(winid) then
    return
  end

  apply_opts(winid, welcome_opts)
end

function M.apply_normal(winid)
  if not is_valid_window(winid) then
    return
  end

  local sess, side = get_session_for_window(winid)
  if not sess or not side then
    return
  end

  M.capture_session_profiles(sess)
  local normal_opts = sess.window_profiles and sess.window_profiles[side]
  if not normal_opts then
    return
  end

  apply_opts(winid, normal_opts)
end

function M.sync(winid)
  if not is_valid_window(winid) then
    return
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  if welcome.is_welcome_buffer(bufnr) then
    M.apply(winid)
  else
    M.apply_normal(winid)
  end
end

function M.sync_later(winid)
  vim.schedule(function()
    M.sync(winid)
  end)
end

return M
