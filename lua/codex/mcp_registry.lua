local uv = vim.loop
local M = {}

local directory_name = 'codex.nvim-mcp'
local directory_mode = 448 -- 0700
local file_mode = 384 -- 0600

function M.directory()
  return vim.fn.stdpath 'cache' .. '/' .. directory_name
end

function M.manifest_path(pid)
  return M.directory() .. '/bridge-' .. tostring(pid) .. '.json'
end

local function ensure_directory()
  local directory = M.directory()
  vim.fn.mkdir(directory, 'p', directory_mode)
  if vim.fn.isdirectory(directory) ~= 1 then
    return nil, 'could not create MCP registry directory: ' .. directory
  end

  if vim.fn.has 'win32' ~= 1 then
    local ok, err = uv.fs_chmod(directory, directory_mode)
    if not ok then
      return nil, 'could not secure MCP registry directory: ' .. tostring(err)
    end
  end
  return directory
end

local function write_manifest(path, contents)
  local temp_path = path .. '.tmp'
  local fd, open_err = uv.fs_open(temp_path, 'w', file_mode)
  if not fd then
    return nil, 'could not create MCP registry manifest: ' .. tostring(open_err)
  end

  local written, write_err = uv.fs_write(fd, contents, 0)
  local closed, close_err = uv.fs_close(fd)
  if not written then
    pcall(uv.fs_unlink, temp_path)
    return nil, 'could not write MCP registry manifest: ' .. tostring(write_err)
  end
  if not closed then
    pcall(uv.fs_unlink, temp_path)
    return nil, 'could not close MCP registry manifest: ' .. tostring(close_err)
  end

  if vim.fn.has 'win32' ~= 1 then
    local secured, chmod_err = uv.fs_chmod(temp_path, file_mode)
    if not secured then
      pcall(uv.fs_unlink, temp_path)
      return nil, 'could not secure MCP registry manifest: ' .. tostring(chmod_err)
    end
  end

  -- Windows rename does not replace an existing file. The current process owns
  -- this manifest path, so removing a stale file for a reused pid is safe.
  pcall(uv.fs_unlink, path)
  local renamed, rename_err = uv.fs_rename(temp_path, path)
  if not renamed then
    pcall(uv.fs_unlink, temp_path)
    return nil, 'could not publish MCP registry manifest: ' .. tostring(rename_err)
  end
  return true
end

function M.publish(socket_path, cwd)
  if type(socket_path) ~= 'string' or socket_path == '' then
    return nil, 'MCP registry requires a socket path'
  end
  if type(cwd) ~= 'string' or cwd == '' then
    return nil, 'MCP registry requires a workspace path'
  end

  local directory, directory_err = ensure_directory()
  if not directory then
    return nil, directory_err
  end

  local pid = uv.os_getpid()
  local manifest_path = M.manifest_path(pid)
  local record = {
    pid = pid,
    socket_path = socket_path,
    cwd = vim.fn.fnamemodify(cwd, ':p'),
  }
  local ok, encoded = pcall(vim.json.encode, record)
  if not ok then
    return nil, 'could not encode MCP registry manifest: ' .. tostring(encoded)
  end

  local written, write_err = write_manifest(manifest_path, encoded)
  if not written then
    return nil, write_err
  end
  return manifest_path
end

local function process_is_alive(pid)
  local ok, result, err = pcall(uv.kill, pid, 0)
  if not ok then
    return false
  end
  return result == 0 or (type(err) == 'string' and err:match '^EPERM' ~= nil)
end

local function read_manifest(path, filename_pid)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end

  local decoded, record = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decoded or type(record) ~= 'table' then
    return nil
  end
  if type(record.pid) ~= 'number' or record.pid % 1 ~= 0 or record.pid ~= filename_pid then
    return nil
  end
  if type(record.socket_path) ~= 'string' or record.socket_path == '' then
    return nil
  end
  if type(record.cwd) ~= 'string' or record.cwd == '' then
    return nil
  end
  if not process_is_alive(record.pid) then
    return nil
  end
  return record
end

local function normalize_path(path)
  local normalized = vim.fn.fnamemodify(path, ':p'):gsub('[\\/]+$', '')
  return normalized == '' and '/' or normalized
end

local function path_segments(path)
  local count = 0
  for _ in path:gmatch '[^/\\]+' do
    count = count + 1
  end
  return count
end

-- Distance in path segments when one workspace contains the other (or they
-- are equal); nil when they are unrelated.
local function workspace_distance(a, b)
  if a == b then
    return 0
  end
  local outer, inner = a, b
  if #outer > #inner then
    outer, inner = inner, outer
  end
  local prefix = outer == '/' and '/' or outer .. '/'
  if inner:sub(1, #prefix) ~= prefix then
    return nil
  end
  return path_segments(inner) - path_segments(outer)
end

function M.find(cwd)
  local directory = M.directory()
  local scan = uv.fs_scandir(directory)
  if not scan then
    return nil, 'no live codex.nvim MCP bridge is registered'
  end

  local live = {}
  while true do
    local name = uv.fs_scandir_next(scan)
    if not name then
      break
    end
    local pid = name:match '^bridge%-(%d+)%.json$'
    if pid then
      local record = read_manifest(directory .. '/' .. name, tonumber(pid))
      if record then
        table.insert(live, record)
      end
    end
  end

  if #live == 0 then
    return nil, 'no live codex.nvim MCP bridge is registered'
  end

  if type(cwd) == 'string' and cwd ~= '' then
    local target = normalize_path(cwd)
    local best, best_distance, tied = nil, nil, false
    for _, record in ipairs(live) do
      local distance = workspace_distance(target, normalize_path(record.cwd))
      if distance and (not best_distance or distance < best_distance) then
        best, best_distance, tied = record, distance, false
      elseif distance and distance == best_distance then
        tied = true
      end
    end
    if best and not tied then
      return best
    elseif tied then
      return nil, 'multiple codex.nvim MCP bridges match workspace ' .. target
    end
  end

  if #live == 1 then
    return live[1]
  end
  return nil, 'multiple codex.nvim MCP bridges are live; start Codex from the matching workspace'
end

function M.resolve(socket_path, cwd)
  if type(socket_path) == 'string' and socket_path ~= '' then
    return { socket_path = socket_path, cwd = cwd }
  end
  return M.find(cwd)
end

function M.remove(manifest_path)
  if type(manifest_path) ~= 'string' or manifest_path == '' then
    return true
  end

  local expected = M.manifest_path(uv.os_getpid())
  if manifest_path ~= expected then
    return nil, 'refusing to remove another process MCP registry manifest'
  end

  local ok, err = uv.fs_unlink(manifest_path)
  if ok or err == 'ENOENT' then
    return true
  end
  return nil, 'could not remove MCP registry manifest: ' .. tostring(err)
end

return M
