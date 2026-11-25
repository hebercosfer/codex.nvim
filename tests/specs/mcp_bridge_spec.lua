local eq = assert.equals

describe('codex MCP bridge', function()
  local original_fn
  local cache_root
  local original_cache_home
  local bridge
  local registry

  before_each(function()
    original_fn = vim.fn
    original_cache_home = vim.env.XDG_CACHE_HOME
    cache_root = original_fn.tempname()
    original_fn.mkdir(cache_root, 'p')
    vim.fn = setmetatable({
      stdpath = function(name)
        if name == 'cache' then
          return cache_root
        end
        return original_fn.stdpath(name)
      end,
    }, { __index = original_fn })
    package.loaded['codex.mcp_registry'] = nil
    package.loaded['codex.mcp_bridge'] = nil
    registry = require 'codex.mcp_registry'
    bridge = require 'codex.mcp_bridge'
  end)

  after_each(function()
    bridge.stop()
    vim.fn = original_fn
    vim.env.XDG_CACHE_HOME = original_cache_home
    original_fn.delete(cache_root, 'rf')
  end)

  it('builds config overrides that enable the running bridge, or disable it when stopped', function()
    local disabled = bridge.config_args()
    eq('mcp_servers.codex_nvim.enabled=false', disabled[2])

    local socket_path = assert(bridge.start(function(_, _, respond)
      respond { tools = {} }
    end))
    local args = bridge.config_args()
    local joined = table.concat(args, '\n')
    assert(joined:find('mcp_servers.codex_nvim.enabled=true', 1, true), 'bridge should be enabled')
    assert(joined:find(socket_path, 1, true), 'bridge socket should be passed to the helper')
    assert(not joined:find('enabled=false', 1, true), 'bridge must not also be disabled')
  end)

  it('publishes a discoverable socket and removes it when stopped', function()
    local socket_path, start_err = bridge.start(function(_, _, respond)
      respond { tools = {} }
    end)

    assert(socket_path, start_err)
    local record, find_err = registry.find(vim.fn.getcwd())
    assert(record, find_err)
    eq(socket_path, record.socket_path)

    bridge.stop()

    local stopped, stop_err = registry.find(vim.fn.getcwd())
    eq(nil, stopped)
    assert(stop_err:match 'no live codex.nvim MCP bridge')
  end)

  it('serves MCP over stdio when the helper discovers the bridge without a socket argument', function()
    vim.fn = original_fn
    vim.env.XDG_CACHE_HOME = cache_root
    local socket_path, start_err = bridge.start(function(method, _, respond)
      if method == 'tools/list' then
        respond { tools = { { name = 'nvimTestTool', inputSchema = { type = 'object' } } } }
      else
        respond(nil, { code = -32601, message = 'unexpected method' })
      end
    end)
    assert(socket_path, start_err)

    local responses = {}
    local exited = false
    local helper = original_fn.getcwd() .. '/lua/codex/mcp_stdio.lua'
    local job = vim.fn.jobstart({ vim.v.progpath, '--headless', '--clean', '-l', helper }, {
      stdin = 'pipe',
      stdout_buffered = false,
      on_stdout = function(_, data)
        for _, line in ipairs(data or {}) do
          if line ~= '' then
            table.insert(responses, line)
          end
        end
      end,
      on_exit = function()
        exited = true
      end,
    })
    assert(job > 0, 'stdio helper should start')
    vim.fn.chansend(job, vim.json.encode {
      jsonrpc = '2.0',
      id = 1,
      method = 'initialize',
      params = { protocolVersion = '2024-11-05', capabilities = {}, clientInfo = { name = 'spec', version = '1' } },
    } .. '\n' .. vim.json.encode { jsonrpc = '2.0', id = 2, method = 'tools/list', params = {} } .. '\n')

    vim.wait(5000, function()
      return #responses >= 2 or exited
    end, 10)
    assert(#responses >= 2, 'stdio helper should return initialize and tools/list responses')
    local list_response = vim.json.decode(responses[2])
    eq('nvimTestTool', list_response.result.tools[1].name)

    vim.fn.chanclose(job, 'stdin')
    vim.wait(1000, function()
      return exited
    end, 10)
    if not exited then
      vim.fn.jobstop(job)
    end
  end)
end)
