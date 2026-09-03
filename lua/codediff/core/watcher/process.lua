local M = {}

local protocol = require("codediff.core.watcher.protocol")
local uv = vim.uv or vim.loop

local READY_TIMEOUT_MS = 10000
local MAX_STDERR_BYTES = 8 * 1024

local function close_handle(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

local function close_pipe(pipe)
  if not pipe or pipe:is_closing() then
    return
  end
  pcall(function()
    pipe:read_stop()
  end)
  pipe:close()
end

function M.start(binary, repository, handlers)
  handlers = handlers or {}
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local ready_timer = uv.new_timer()
  local handle
  local spawn_error
  local stopped = false
  local failed = false
  local ready = false
  local stderr_text = ""

  local function stop_ready_timer()
    if not ready_timer then
      return
    end
    if not ready_timer:is_closing() then
      ready_timer:stop()
      ready_timer:close()
    end
    ready_timer = nil
  end

  local function terminate()
    stop_ready_timer()
    close_pipe(stdout)
    close_pipe(stderr)
    if handle and not handle:is_closing() then
      pcall(function()
        handle:kill("sigterm")
      end)
    end
  end

  local function report_error(message)
    if stopped or failed then
      return
    end
    failed = true
    terminate()
    if handlers.on_error then
      handlers.on_error(message)
    end
  end

  local decoder = protocol.new({
    on_ready = function(message)
      if stopped or failed then
        return
      end
      ready = true
      stop_ready_timer()
      if handlers.on_ready then
        handlers.on_ready(message)
      end
    end,
    on_refresh = function(message)
      if not stopped and not failed and handlers.on_refresh then
        handlers.on_refresh(message)
      end
    end,
    on_error = report_error,
  })

  handle, spawn_error = uv.spawn(binary, {
    args = { repository },
    cwd = repository,
    hide = true,
    stdio = { nil, stdout, stderr },
  }, function(code, signal)
    vim.schedule(function()
      close_pipe(stdout)
      close_pipe(stderr)
      close_handle(handle)
      stop_ready_timer()
      if stopped or failed then
        return
      end
      local detail = stderr_text:gsub("%s+$", "")
      local message = string.format("codediff-watcher exited with code %d (signal %d)", code, signal)
      if detail ~= "" then
        message = message .. ": " .. detail
      end
      report_error(message)
    end)
  end)

  if not handle then
    close_pipe(stdout)
    close_pipe(stderr)
    stop_ready_timer()
    return nil, "failed to start codediff-watcher: " .. tostring(spawn_error)
  end

  stdout:read_start(function(err, chunk)
    vim.schedule(function()
      if stopped or failed then
        return
      end
      if err then
        report_error("failed to read codediff-watcher stdout: " .. err)
      elseif chunk then
        decoder.feed(chunk)
      else
        decoder.finish()
      end
    end)
  end)

  stderr:read_start(function(_, chunk)
    if chunk and #stderr_text < MAX_STDERR_BYTES then
      stderr_text = (stderr_text .. chunk):sub(1, MAX_STDERR_BYTES)
    end
  end)

  ready_timer:start(
    READY_TIMEOUT_MS,
    0,
    vim.schedule_wrap(function()
      if not ready then
        report_error("codediff-watcher did not report ready within 10 seconds")
      end
    end)
  )

  local process = {}

  function process.stop()
    if stopped then
      return
    end
    stopped = true
    terminate()
  end

  function process.is_ready()
    return ready
  end

  return process
end

return M
