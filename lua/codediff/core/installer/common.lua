local M = {}

-- Termux reports Linux through LuaJIT but requires Android binaries.
local function is_termux()
  local termux_version = vim.fn.getenv("TERMUX_VERSION")
  if termux_version ~= vim.NIL and termux_version ~= "" then
    return true
  end
  local prefix = vim.fn.getenv("PREFIX")
  return type(prefix) == "string" and prefix:match("^/data/data/com%.termux") ~= nil
end

function M.detect_os()
  local os_name = require("ffi").os
  if os_name == "Windows" then
    return "windows"
  elseif os_name == "OSX" then
    return "macos"
  elseif is_termux() then
    return "android"
  end
  return "linux"
end

function M.detect_arch()
  local ffi = require("ffi")
  if ffi.os == "Windows" then
    -- Prefer the host architecture when Neovim is a 32-bit process.
    local process_arch = vim.fn.getenv("PROCESSOR_ARCHITECTURE")
    local process_arch_w6432 = vim.fn.getenv("PROCESSOR_ARCHITEW6432")
    local arch = process_arch_w6432 ~= vim.NIL and process_arch_w6432 or process_arch
    if arch then
      arch = arch:lower()
      if arch:match("amd64") or arch:match("x64") then
        return "x64"
      elseif arch:match("arm64") then
        return "arm64"
      end
    end
  end

  local machine = (vim.uv or vim.loop).os_uname().machine:lower()
  if machine:match("x86_64") or machine:match("amd64") or machine:match("x64") then
    return "x64"
  elseif machine:match("aarch64") or machine:match("arm64") then
    return "arm64"
  end
  return nil, "Unsupported architecture: " .. (machine or "unknown")
end

function M.command_exists(command)
  local windows = require("ffi").os == "Windows"
  local check = windows and "where " .. command .. " 2>nul" or "which " .. command .. " 2>/dev/null"
  local handle = io.popen(check)
  if not handle then
    return false
  end
  local result = handle:read("*a")
  handle:close()

  if result == "" and not windows then
    handle = io.popen("type " .. command .. " 2>/dev/null")
    if handle then
      result = handle:read("*a")
      handle:close()
    end
  end
  return result ~= ""
end

function M.run(command)
  if vim.system then
    local result = vim.system(command, { text = true }):wait()
    if result.code == 0 then
      return true, result.stdout or ""
    end
    return false, result.stderr or result.stdout or "Unknown error"
  end

  local shell_command = table.concat(
    vim.tbl_map(function(argument)
      return string.format("'%s'", argument:gsub("'", "'\\''"))
    end, command),
    " "
  )
  local exit_code = os.execute(shell_command)
  if exit_code == true or exit_code == 0 then
    return true, ""
  end
  return false, tostring(exit_code)
end

function M.download_file(url, destination)
  local command
  if M.command_exists("curl") then
    command = { "curl", "-fsSL", "-o", destination, url }
  elseif M.command_exists("wget") then
    command = { "wget", "-q", "-O", destination, url }
  elseif require("ffi").os == "Windows" then
    command = {
      "powershell",
      "-NoProfile",
      "-Command",
      string.format("Invoke-WebRequest -Uri '%s' -OutFile '%s'", url, destination),
    }
  else
    return false, "No download tool found. Please install curl or wget."
  end

  local uses_vim_system = vim.system ~= nil
  local ok, err = M.run(command)
  if ok then
    return true
  elseif uses_vim_system then
    return false, "Download failed: " .. err
  end
  return false, "Download failed with exit code: " .. err
end

function M.download(options)
  if not options.silent then
    vim.notify(string.format("Installing %s v%s for %s %s...", options.name, options.version, options.os, options.arch), vim.log.levels.INFO)
    vim.notify("Downloading from: " .. options.url, vim.log.levels.INFO)
  end
  return M.download_file(options.url, options.destination)
end

function M.notify_success(name, silent)
  if not silent then
    vim.notify("Successfully installed " .. name .. "!", vim.log.levels.INFO)
  end
end

return M
