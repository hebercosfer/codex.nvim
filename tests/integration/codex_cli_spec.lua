-- luacheck: globals describe it assert eq before_each after_each pending

-- Contract checks against a real Codex CLI, so a drift in the CLI shows up here
-- rather than in somebody's editor. Runs only when CODEX_BIN names a binary;
-- otherwise it is pending.
local codex_bin = os.getenv 'CODEX_BIN'
if not codex_bin or codex_bin == '' then
  describe('codex CLI contract', function()
    pending 'set CODEX_BIN to run the codex CLI contract checks'
  end)
  return
end

local eq = assert.equals
local ws_rpc = require 'codex.ws_rpc'

-- The flags the plugin passes, and the subcommand each one belongs to.
local flags = {
  { cmd = '', flag = '--remote' },
  { cmd = '', flag = '--cd' },
  { cmd = '', flag = '--config' },
  { cmd = '', flag = '--dangerously-bypass-approvals-and-sandbox' },
  { cmd = 'app-server', flag = '--listen' },
  { cmd = 'app-server', flag = '--enable' },
  { cmd = 'resume', flag = '--last' },
}

local function help_for(cmd)
  local argv = { codex_bin }
  if cmd ~= '' then
    table.insert(argv, cmd)
  end
  table.insert(argv, '--help')
  return vim.fn.system(argv)
end

-- A random high port per run; the spec waits for it to accept connections.
local function pick_port()
  return 45000 + math.random(0, 900)
end

describe('codex CLI contract', function()
  local app_server_job

  after_each(function()
    if app_server_job then
      pcall(vim.fn.jobstop, app_server_job)
      app_server_job = nil
    end
  end)

  it('reports a version', function()
    local out = vim.fn.system { codex_bin, '--version' }
    eq(0, vim.v.shell_error, 'codex --version failed: ' .. out)
    assert(out:match '%d+%.%d+%.%d+', 'no version in output: ' .. out)
  end)

  for _, check in ipairs(flags) do
    local label = (check.cmd ~= '' and (check.cmd .. ' ') or '') .. check.flag
    it('still accepts ' .. label, function()
      local out = help_for(check.cmd)
      assert(out:find(check.flag, 1, true), label .. ' is missing from `' .. (check.cmd ~= '' and check.cmd or 'codex') .. ' --help`')
    end)
  end

  it('completes the app-server initialize handshake the plugin uses', function()
    local port = pick_port()
    local url = ('ws://127.0.0.1:%d'):format(port)
    app_server_job = vim.fn.jobstart({ codex_bin, 'app-server', '--listen', url }, { detach = false })
    assert(app_server_job > 0, 'could not start `codex app-server`')

    local client
    local connected
    local attempt_running = false
    local ok = vim.wait(20000, function()
      if connected then
        return true
      end
      if not attempt_running then
        -- app-server takes a moment to listen; start() reports false until it does, so retry.
        attempt_running = true
        connected = nil
        client = ws_rpc.new {
          url = url,
          on_notification = function() end,
          on_request = function() end,
        }
        client:start(function(started)
          connected = started == true
          attempt_running = false
        end)
      end
      return false
    end, 200)
    assert(ok and connected, 'app-server never accepted a websocket connection on ' .. url)

    local init_err, init_result
    client:request('initialize', {
      clientInfo = { name = 'codex_nvim', title = 'codex.nvim', version = 'contract' },
      capabilities = { experimentalApi = true },
    }, function(err, result)
      init_err = err
      init_result = result
    end)
    assert(
      vim.wait(10000, function()
        return init_result ~= nil or init_err ~= nil
      end, 50),
      'no response to initialize'
    )
    assert(init_err == nil, 'initialize returned an error: ' .. vim.inspect(init_err))
    assert(init_result, 'initialize returned no result')

    client:notify('initialized', {})
    client:stop()
  end)
end)
