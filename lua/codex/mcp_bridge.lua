local logger = require 'codex.logger'

local uv = vim.loop
local M = {
  clients = {},
}

local function close(handle)
  if not handle then
    return
  end
  pcall(function()
    handle:read_stop()
  end)
  if not handle:is_closing() then
    handle:close()
  end
end

local function socket_path()
  if vim.fn.has('win32') == 1 then
    local id = vim.fn.sha256(vim.fn.tempname()):sub(1, 24)
    return [[\\.\pipe\]] .. 'codex.nvim.' .. id
  end
  return vim.fn.tempname() .. '.sock'
end

local function remove_client(client)
  M.clients[client] = nil
  close(client)
end

local function write_response(client, response)
  if not M.clients[client] or client:is_closing() then
    return
  end

  local ok, encoded = pcall(vim.json.encode, response)
  if not ok then
    logger.warn('could not encode MCP bridge response:', tostring(encoded))
    remove_client(client)
    return
  end

  client:write(encoded .. '\n', function(err)
    if err then
      remove_client(client)
    end
  end)
end

local function send_error(client, id, code, message)
  write_response(client, {
    jsonrpc = '2.0',
    id = id,
    error = { code = code, message = message },
  })
end

local function dispatch_request(client, request)
  if not M.clients[client] then
    return
  end

  if type(request) ~= 'table' or type(request.method) ~= 'string' or request.id == nil then
    if type(request) == 'table' and request.id ~= nil then
      send_error(client, request.id, -32600, 'Invalid request')
    end
    return
  end

  if request.method ~= 'tools/list' and request.method ~= 'tools/call' then
    send_error(client, request.id, -32601, 'Method not found')
    return
  end

  if not M.dispatch then
    send_error(client, request.id, -32000, 'Neovim tool bridge is stopping')
    return
  end

  local responded = false
  local function respond(result, err)
    if responded then
      return
    end
    responded = true
    if err then
      send_error(client, request.id, err.code or -32603, err.message or tostring(err))
    else
      write_response(client, {
        jsonrpc = '2.0',
        id = request.id,
        result = result,
      })
    end
  end

  local ok, err = pcall(M.dispatch, request.method, request.params or {}, respond)
  if not ok then
    respond(nil, { code = -32603, message = tostring(err) })
  end
end

local function read_client(client, err, chunk)
  local state = M.clients[client]
  if not state then
    return
  end
  if err or not chunk then
    remove_client(client)
    return
  end

  state.buffer = state.buffer .. chunk
  while true do
    local newline = state.buffer:find('\n', 1, true)
    if not newline then
      break
    end

    local line = state.buffer:sub(1, newline - 1)
    state.buffer = state.buffer:sub(newline + 1)
    if line ~= '' then
      local ok, request = pcall(vim.json.decode, line)
      if not ok then
        send_error(client, vim.NIL, -32700, 'Parse error')
      else
        vim.schedule(function()
          dispatch_request(client, request)
        end)
      end
    end
  end
end

local function accept_client(server, err)
  if err then
    logger.warn('MCP bridge accept failed:', tostring(err))
    return
  end
  if M.server ~= server then
    return
  end

  local client = uv.new_pipe(false)
  local ok, accept_err = server:accept(client)
  if not ok then
    close(client)
    logger.warn('MCP bridge client accept failed:', tostring(accept_err))
    return
  end

  M.clients[client] = { buffer = '' }
  client:read_start(function(read_err, chunk)
    read_client(client, read_err, chunk)
  end)
end

function M.start(dispatch)
  if M.server then
    M.dispatch = dispatch or M.dispatch
    return M.socket_path
  end
  if type(dispatch) ~= 'function' then
    return nil, 'MCP bridge dispatch callback is required'
  end

  local path = socket_path()
  local server = uv.new_pipe(false)
  local bound, bind_err = server:bind(path)
  if not bound then
    close(server)
    return nil, tostring(bind_err or 'failed to bind MCP bridge socket')
  end

  M.server = server
  M.socket_path = path
  M.dispatch = dispatch
  local listening, listen_err = server:listen(64, function(err)
    accept_client(server, err)
  end)
  if not listening then
    M.stop()
    return nil, tostring(listen_err or 'failed to listen on MCP bridge socket')
  end

  if vim.fn.has('win32') ~= 1 and uv.fs_chmod then
    pcall(uv.fs_chmod, path, 384)
  end
  return path
end

function M.launch_config()
  if not M.socket_path then
    return nil
  end

  local source = debug.getinfo(1, 'S').source
  if source:sub(1, 1) == '@' then
    source = source:sub(2)
  end
  local plugin_root = vim.fn.fnamemodify(source, ':p:h:h:h')
  return {
    command = vim.v.progpath,
    args = {
      '--headless',
      '--clean',
      '-l',
      plugin_root .. '/lua/codex/mcp_stdio.lua',
      M.socket_path,
    },
  }
end

function M.stop()
  M.dispatch = nil
  for client in pairs(M.clients) do
    remove_client(client)
  end

  local server = M.server
  local path = M.socket_path
  M.server = nil
  M.socket_path = nil
  close(server)
  if path and vim.fn.has('win32') ~= 1 then
    pcall(uv.fs_unlink, path)
  end
end

return M
