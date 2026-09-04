local M = {}

local MAX_LINE_BYTES = 64 * 1024

local function decode(line)
  if vim.json and vim.json.decode then
    return vim.json.decode(line)
  end
  return vim.fn.json_decode(line)
end

local function is_boolean(value)
  return value == true or value == false
end

function M.new(handlers)
  handlers = handlers or {}
  local buffer = ""
  local ready = false
  local failed = false

  local function fail(message)
    if failed then
      return
    end
    failed = true
    if handlers.on_error then
      handlers.on_error(message)
    end
  end

  local function dispatch(line)
    if line == "" then
      fail("watcher wrote an empty protocol line")
      return
    end

    local ok, message = pcall(decode, line)
    if not ok or type(message) ~= "table" then
      fail("watcher wrote invalid JSON")
      return
    end

    if not ready then
      if message.type ~= "ready" or message.protocol ~= 1 or type(message.binary_version) ~= "string" then
        fail("watcher did not start with a protocol 1 ready message")
        return
      end
      ready = true
      if handlers.on_ready then
        handlers.on_ready(message)
      end
      return
    end

    if message.type ~= "refresh" then
      fail("watcher wrote an unknown message type")
      return
    end
    if not is_boolean(message.worktree) or not is_boolean(message.index) or not is_boolean(message.head) or not is_boolean(message.refs) then
      fail("watcher refresh fields must be boolean")
      return
    end
    if handlers.on_refresh then
      handlers.on_refresh(message)
    end
  end

  local protocol = {}

  function protocol.feed(chunk)
    if failed or not chunk or chunk == "" then
      return
    end
    buffer = buffer .. chunk
    while not failed do
      local newline = buffer:find("\n", 1, true)
      if not newline then
        break
      end
      if newline - 1 > MAX_LINE_BYTES then
        fail("watcher protocol line exceeded 64 KiB")
        break
      end
      local line = buffer:sub(1, newline - 1):gsub("\r$", "")
      buffer = buffer:sub(newline + 1)
      dispatch(line)
    end
    if not failed and #buffer > MAX_LINE_BYTES then
      fail("watcher protocol line exceeded 64 KiB")
    end
  end

  function protocol.finish()
    if failed then
      return
    end
    if buffer ~= "" then
      fail("watcher stdout ended with an incomplete protocol line")
    elseif not ready then
      fail("watcher exited before reporting ready")
    end
  end

  function protocol.is_ready()
    return ready
  end

  function protocol.has_failed()
    return failed
  end

  return protocol
end

return M
