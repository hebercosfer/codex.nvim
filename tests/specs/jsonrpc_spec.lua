-- luacheck: globals describe it assert eq before_each after_each

local eq = assert.equals
local jsonrpc = require 'codex.jsonrpc'

-- Waits until scheduled callbacks have run (the client dispatches through vim.schedule).
local function flush()
  vim.wait(100, function()
    return false
  end, 5)
end

describe('codex.jsonrpc', function()
  local orig_fn
  local started_with
  local stopped
  local sent
  local job_handlers

  before_each(function()
    orig_fn = vim.fn
    started_with, stopped, sent, job_handlers = nil, nil, {}, nil
    vim.fn = setmetatable({
      jobstart = function(cmd, opts)
        started_with = cmd
        job_handlers = opts
        return 42
      end,
      jobstop = function(job)
        stopped = job
      end,
      chansend = function(_, data)
        table.insert(sent, data)
      end,
    }, { __index = orig_fn })
  end)

  after_each(function()
    vim.fn = orig_fn
  end)

  local function running_client(callbacks)
    local client = jsonrpc.new(vim.tbl_extend('force', { cmd = { 'codex', 'app-server' } }, callbacks or {}))
    assert(client:start())
    return client
  end

  it('starts the command and reports that it is running', function()
    local client = running_client()
    eq('codex', started_with[1])
    eq(true, client:is_running())
  end)

  it('starts only once', function()
    local client = running_client()
    eq(true, client:start())
    eq(42, client.job)
  end)

  it('stops the job and forgets it', function()
    local client = running_client()
    client:stop()
    eq(42, stopped)
    eq(false, client:is_running())
  end)

  it('reports a failure to start', function()
    vim.fn.jobstart = function()
      return -1
    end
    local client = jsonrpc.new { cmd = { 'missing' } }
    local ok, err = client:start()
    eq(false, ok)
    eq('failed to start job', err)
  end)

  it('sends a request with an id and calls back with its result', function()
    local client = running_client()
    local got_result
    local id = client:request('initialize', { version = '1' }, function(err, result)
      got_result = { err = err, result = result }
    end)
    eq(1, id)
    local request = vim.json.decode(sent[1])
    eq(1, request.id)
    eq('initialize', request.method)
    eq('1', request.params.version)

    client:_handle_line '{"id":1,"result":{"ok":true}}'
    flush()
    eq(true, got_result.result.ok)
    eq(nil, got_result.err)
  end)

  it('passes an error response to the request callback', function()
    local client = running_client()
    local got_err
    client:request('thread/start', {}, function(err)
      got_err = err
    end)
    client:_handle_line '{"id":1,"error":{"code":-1,"message":"boom"}}'
    flush()
    eq('boom', got_err.message)
  end)

  it('sends notifications without an id', function()
    local client = running_client()
    client:notify('initialized', nil)
    local notification = vim.json.decode(sent[1])
    eq('initialized', notification.method)
    eq(nil, notification.id)
  end)

  it('hands server notifications to on_notification', function()
    local seen
    local client = running_client {
      on_notification = function(msg)
        seen = msg
      end,
    }
    client:_handle_line '{"method":"thread/started","params":{"id":"t1"}}'
    flush()
    eq('thread/started', seen.method)
    eq('t1', seen.params.id)
  end)

  it('answers server requests through on_request', function()
    local client = running_client {
      on_request = function(_msg, respond)
        respond({ decision = 'accept' }, nil)
      end,
    }
    client:_handle_line '{"id":9,"method":"item/commandExecution/requestApproval","params":{}}'
    flush()
    local response = vim.json.decode(sent[1])
    eq(9, response.id)
    eq('accept', response.result.decision)
  end)

  it('answers unhandled server requests with method not found', function()
    local client = running_client()
    client:_handle_line '{"id":3,"method":"unknown/thing","params":{}}'
    flush()
    assert(sent[1]:find('"code":-32601', 1, true), 'expected a method-not-found error, got ' .. sent[1])
  end)

  it('reassembles a line split across stdout chunks', function()
    local seen = {}
    local client = running_client {
      on_notification = function(msg)
        table.insert(seen, msg.method)
      end,
    }
    client:_on_stdout { '{"method":"one","params":{}}', '{"method":"tw' }
    client:_on_stdout { 'o","params":{}}', '' }
    flush()
    eq('one,two', table.concat(seen, ','))
  end)

  it('logs and skips a line that is not JSON', function()
    local seen = 0
    local client = running_client {
      on_notification = function()
        seen = seen + 1
      end,
    }
    client:_handle_line 'not json at all'
    flush()
    eq(0, seen)
  end)

  it('forwards stderr lines to on_stderr', function()
    local lines = {}
    local client = running_client {
      on_stderr = function(line)
        table.insert(lines, line)
      end,
    }
    client:_on_stderr { 'warning: something', '' }
    flush()
    eq('warning: something', lines[1])
    eq(1, #lines)
  end)

  it('clears the job and calls on_exit when the process exits', function()
    local exit_code
    local client = running_client {
      on_exit = function(code)
        exit_code = code
      end,
    }
    job_handlers.on_exit(42, 3)
    flush()
    eq(3, exit_code)
    eq(false, client:is_running())
  end)

  it('fails a request straight away when the client is not running', function()
    local client = jsonrpc.new { cmd = { 'codex' } }
    local got_err
    local ok, err = client:send { method = 'ping' }
    eq(false, ok)
    eq('app-server is not running', err)
    client:request('ping', {}, function(e)
      got_err = e
    end)
    eq('app-server is not running', got_err.message)
  end)
end)
