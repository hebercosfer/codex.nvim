local uv = vim.loop

local function explicit_socket_path()
  for index, value in ipairs(vim.v.argv) do
    if value == '-l' then
      local candidate = vim.v.argv[index + 2]
      if candidate == '--' then
        candidate = vim.v.argv[index + 3]
      end
      return candidate ~= '' and candidate or nil
    end
  end
  if arg and type(arg[1]) == 'string' and arg[1] ~= '' then
    return arg[1]
  end
end

local socket_path = explicit_socket_path()

if not socket_path then
  local source = debug.getinfo(1, 'S').source
  if source:sub(1, 1) == '@' then
    source = source:sub(2)
  end
  local plugin_root = vim.fn.fnamemodify(source, ':p:h:h:h')
  vim.opt.runtimepath:prepend(plugin_root)

  local loaded, registry = pcall(require, 'codex.mcp_registry')
  if not loaded then
    io.stderr:write('could not load codex.nvim MCP registry: ', tostring(registry), '\n')
    io.stderr:flush()
    os.exit(1)
  end

  local record, registry_err = registry.resolve(nil, vim.fn.getcwd())
  if not record then
    io.stderr:write('could not discover a codex.nvim MCP bridge: ', tostring(registry_err), '\n')
    io.stderr:flush()
    os.exit(1)
  end
  socket_path = record.socket_path
end

local function write_stderr(message)
  io.stderr:write(tostring(message), '\n')
  io.stderr:flush()
end

local function write_stdout(value)
  local ok, encoded = pcall(vim.json.encode, value)
  if not ok then
    write_stderr('could not encode MCP response: ' .. tostring(encoded))
    return false
  end
  io.stdout:write(encoded, '\n')
  io.stdout:flush()
  return true
end

if not socket_path or socket_path == '' then
  write_stderr 'codex.nvim MCP helper did not receive its socket path'
  os.exit(1)
end

local socket = uv.new_pipe(false)
local socket_error
local connected = false
local response_buffer = ''
local pending_response
local next_id = 0

socket:connect(socket_path, function(err)
  if err then
    socket_error = tostring(err)
  else
    connected = true
  end
end)

local function wait_for(predicate)
  while not predicate() do
    if socket_error then
      return false
    end
    local active = uv.run 'once'
    if not active and not predicate() then
      return false
    end
  end
  return true
end

if not wait_for(function()
  return connected or socket_error ~= nil
end) then
  write_stderr('could not connect to codex.nvim MCP bridge: ' .. tostring(socket_error or 'connection stopped'))
  pcall(socket.close, socket)
  os.exit(1)
end

socket:read_start(function(err, chunk)
  if err or not chunk then
    socket_error = tostring(err or 'Neovim MCP bridge closed the connection')
    return
  end

  response_buffer = response_buffer .. chunk
  while true do
    local newline = response_buffer:find('\n', 1, true)
    if not newline then
      break
    end
    local line = response_buffer:sub(1, newline - 1)
    response_buffer = response_buffer:sub(newline + 1)
    if line ~= '' then
      local ok, response = pcall(vim.json.decode, line)
      if ok and type(response) == 'table' and response.id == next_id then
        pending_response = response
      end
    end
  end
end)

local function bridge_request(method, params)
  next_id = next_id + 1
  pending_response = nil
  local request = {
    jsonrpc = '2.0',
    id = next_id,
    method = method,
    params = params or {},
  }
  local ok, encoded = pcall(vim.json.encode, request)
  if not ok then
    return nil, tostring(encoded)
  end

  socket:write(encoded .. '\n')
  if not wait_for(function()
    return pending_response ~= nil or socket_error ~= nil
  end) then
    return nil, tostring(socket_error or 'Neovim MCP bridge stopped responding')
  end
  if pending_response.error then
    return nil, pending_response.error.message or 'Neovim MCP bridge request failed'
  end
  return pending_response.result
end

local function jsonrpc_error(id, code, message)
  return {
    jsonrpc = '2.0',
    id = id,
    error = { code = code, message = message },
  }
end

local function handle_message(message)
  if type(message) ~= 'table' or type(message.method) ~= 'string' then
    return jsonrpc_error(type(message) == 'table' and message.id or vim.NIL, -32600, 'Invalid request')
  end

  local method = message.method
  if method == 'notifications/initialized' or method == 'notifications/cancelled' then
    return nil
  end

  if message.id == nil then
    return nil
  end

  if method == 'initialize' then
    local params = message.params or {}
    return {
      jsonrpc = '2.0',
      id = message.id,
      result = {
        protocolVersion = params.protocolVersion or '2024-11-05',
        capabilities = { tools = { listChanged = false } },
        serverInfo = { name = 'codex.nvim', version = '0.1.0' },
      },
    }
  end

  if method == 'ping' then
    return { jsonrpc = '2.0', id = message.id, result = {} }
  end

  if method == 'tools/list' or method == 'tools/call' then
    local result, err = bridge_request(method, message.params or {})
    if err then
      return jsonrpc_error(message.id, -32603, err)
    end
    return { jsonrpc = '2.0', id = message.id, result = result }
  end

  return jsonrpc_error(message.id, -32601, 'Method not found')
end

while true do
  local line = io.stdin:read '*l'
  if line == nil then
    break
  end

  local ok, message = pcall(vim.json.decode, line)
  local response
  if not ok then
    response = jsonrpc_error(vim.NIL, -32700, 'Parse error')
  else
    local handled, result = pcall(handle_message, message)
    if handled then
      response = result
    else
      response = jsonrpc_error(type(message) == 'table' and message.id or vim.NIL, -32603, tostring(result))
    end
  end

  if response and not write_stdout(response) then
    break
  end
end

pcall(socket.read_stop, socket)
pcall(socket.close, socket)
os.exit(0)
