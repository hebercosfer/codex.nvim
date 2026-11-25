local eq = assert.equals
local same = assert.same

describe('codex app-server support', function()
  local original_cwd
  local original_fn
  local test_cleanup

  before_each(function()
    original_cwd = vim.fn.getcwd()
    original_fn = vim.fn
  end)

  after_each(function()
    if test_cleanup then
      test_cleanup()
      test_cleanup = nil
    end
    if original_fn then
      vim.fn = original_fn
    end
    if original_cwd then
      vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
    end
  end)

  it('registers Neovim dynamic tools', function()
    package.loaded['codex.tools'] = nil
    local tools = require 'codex.tools'
    local specs = tools.get_specs()

    local names = {}
    for _, spec in ipairs(specs) do
      names[spec.name] = spec
    end

    assert(names.openFile, 'openFile tool missing')
    assert(names.getCurrentSelection, 'getCurrentSelection tool missing')
    assert(names.getDiagnostics, 'getDiagnostics tool missing')
    eq('nvim', names.openFile.namespace)
  end)

  it('routes App Server MCP requests through the Neovim tool registry', function()
    local old_tools = package.loaded['codex.tools']
    local old_bridge = package.loaded['codex.mcp_bridge']
    local old_jsonrpc = package.loaded['codex.jsonrpc']
    local old_process = package.loaded['codex.app_server_process']
    local old_app_server = package.loaded['codex.app_server']
    local old_state = package.loaded['codex.state']
    package.loaded['codex.tools'] = {
      register_all = function() end,
      get_specs = function()
        return { { name = 'threadTool' } }
      end,
      get_mcp_specs = function()
        return { { name = 'mcpTool' } }
      end,
      handle_mcp = function(params, respond)
        respond { name = params.name }
      end,
    }
    local dispatch
    package.loaded['codex.mcp_bridge'] = {
      start = function(handler)
        dispatch = handler
        return '/tmp/codex-test.sock'
      end,
      stop = function() end,
    }
    local client = {
      start = function()
        return true
      end,
      request = function(_, method, _, callback)
        if method == 'thread/start' then
          callback(nil, { thread = { id = 'thread-1', sessionId = 'session-1' } })
        else
          callback(nil, {})
        end
      end,
      notify = function() end,
      stop = function() end,
    }
    local client_options
    package.loaded['codex.jsonrpc'] = {
      new = function(options)
        client_options = options
        return client
      end,
    }
    package.loaded['codex.app_server_process'] = { stop = function() end }
    package.loaded['codex.app_server'] = nil
    package.loaded['codex.state'] = nil

    local app_server = require 'codex.app_server'
    test_cleanup = function()
      app_server.stop()
      package.loaded['codex.tools'] = old_tools
      package.loaded['codex.mcp_bridge'] = old_bridge
      package.loaded['codex.jsonrpc'] = old_jsonrpc
      package.loaded['codex.app_server_process'] = old_process
      package.loaded['codex.app_server'] = old_app_server
      package.loaded['codex.state'] = old_state
    end

    app_server.setup({
      cmd = { 'codex', '--verbose' },
      model = 'gpt-test',
      app_server = {
        ui = 'buffer',
        dynamic_tools = true,
        listen = 'ws://127.0.0.1:45555',
        enable_features = { 'feature-one', 'feature-two' },
        service_name = 'codex.nvim',
      },
    }, 'test')

    local started
    app_server.start(function(ok)
      started = ok
    end)

    assert(started, 'App Server should initialize')
    same({
      'codex',
      '--verbose',
      '--config',
      'mcp_servers.codex_nvim.enabled=false',
      'app-server',
      '--listen',
      'ws://127.0.0.1:45555',
      '--enable',
      'feature-one',
      '--enable',
      'feature-two',
    }, client_options.cmd)

    local listed
    dispatch('tools/list', {}, function(result)
      listed = result
    end)
    same({ { name = 'mcpTool' } }, listed.tools)

    local called
    dispatch('tools/call', { name = 'mcpTool' }, function(result)
      called = result
    end)
    same({ name = 'mcpTool' }, called)

    local error
    dispatch('unknown/method', {}, function(_, err)
      error = err
    end)
    eq(-32601, error.code)
    eq('Method not found: unknown/method', error.message)
  end)

  it('keeps the MCP bridge available in buffer UI when dynamic tools are enabled', function()
    local global_fn = vim.fn
    local cache_root = original_fn.tempname()
    original_fn.mkdir(cache_root, 'p')
    vim.fn = setmetatable({
      stdpath = function(name)
        if name == 'cache' then
          return cache_root
        end
        return original_fn.stdpath(name)
      end,
    }, { __index = original_fn })

    local old_registry = package.loaded['codex.mcp_registry']
    local old_bridge = package.loaded['codex.mcp_bridge']
    local old_app_server = package.loaded['codex.app_server']
    package.loaded['codex.mcp_registry'] = nil
    package.loaded['codex.mcp_bridge'] = nil
    package.loaded['codex.app_server'] = nil

    local registry = require 'codex.mcp_registry'
    local bridge = require 'codex.mcp_bridge'
    local app_server = require 'codex.app_server'
    local state = require 'codex.state'
    local old_app = state.app
    state.app = {
      client = {
        is_running = function()
          return true
        end,
      },
      initialized = true,
      cwd = original_fn.getcwd(),
      thread_id = 'existing-thread',
    }

    test_cleanup = function()
      bridge.stop()
      state.app = old_app
      package.loaded['codex.mcp_registry'] = old_registry
      package.loaded['codex.mcp_bridge'] = old_bridge
      package.loaded['codex.app_server'] = old_app_server
      vim.fn = global_fn
      original_fn.delete(cache_root, 'rf')
    end

    app_server.setup({ app_server = { ui = 'buffer', dynamic_tools = true } }, 'test')
    local started
    app_server.start(function(ok)
      started = ok
    end)

    assert(started, 'App Server should remain available')
    local record, err = registry.find(original_fn.getcwd())
    assert(record, err)
  end)

  it('tracks range selections with zero-based protocol positions', function()
    local selection = require 'codex.selection'
    vim.cmd 'enew'
    vim.api.nvim_buf_set_name(0, '/tmp/codex-selection-test.lua')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha', 'beta', 'gamma' })

    local sel = selection.get_range_selection(2, 3)

    assert(sel, 'selection should be captured')
    eq('beta\ngamma', sel.text)
    eq(1, sel.selection.start.line)
    eq(2, sel.selection['end'].line)
  end)

  it('restarts the websocket app-server when the Neovim cwd changes', function()
    package.loaded['codex.state'] = nil
    package.loaded['codex.app_server_process'] = nil
    local state = require 'codex.state'
    local app_process = require 'codex.app_server_process'
    local starts = {}
    local stopped = {}
    local exits = {}
    local first_dir = '/tmp/codex-nvim-workspace-one'
    local second_dir = '/tmp/codex-nvim-workspace-two'
    vim.fn.mkdir(first_dir, 'p')
    vim.fn.mkdir(second_dir, 'p')

    vim.fn = setmetatable({
      jobstart = function(cmd, opts)
        local job = 101 + #starts
        table.insert(starts, { cmd = cmd, cwd = opts.cwd, env = opts.env, job = job })
        exits[job] = opts.on_exit
        return job
      end,
      jobstop = function(job)
        table.insert(stopped, job)
      end,
    }, { __index = original_fn })

    local config = {
      cmd = { 'codex' },
      app_server = {
        port_range = { min = 45000, max = 45999 },
        enable_features = {},
      },
    }

    vim.cmd('cd ' .. vim.fn.fnameescape(first_dir))
    app_process.start(config, function(ok)
      assert(ok, 'first app-server start should succeed')
    end)
    app_process.start(config, function(ok)
      assert(ok, 'same-cwd app-server reuse should succeed')
    end)

    vim.cmd('cd ' .. vim.fn.fnameescape(second_dir))
    app_process.start(config, function(ok)
      assert(ok, 'second app-server start should succeed')
    end)

    eq(2, #starts)
    eq(first_dir, starts[1].cwd)
    eq(second_dir, starts[2].cwd)
    assert(vim.tbl_contains(starts[1].cmd, '--config'), 'App Server should isolate the global Neovim MCP entry')
    assert(
      vim.tbl_contains(starts[1].cmd, 'mcp_servers.codex_nvim.enabled=false'),
      'App Server should use its thread dynamic tools instead of the global MCP entry'
    )
    local expected_env = require('codex.util').codex_env()
    eq(expected_env.EDITOR, starts[1].env.EDITOR)
    eq(expected_env.VISUAL, starts[1].env.VISUAL)
    eq(1, #stopped)
    eq(101, stopped[1])
    eq(second_dir, state.app.cwd)
    exits[101](101, 0)
    eq(102, state.app.server_job)
    eq(second_dir, state.app.cwd)

    app_process.stop()
  end)

  it('launches the remote terminal with cwd so native /resume can toggle cwd and all', function()
    package.loaded['codex'] = nil
    package.loaded['codex.app_server'] = nil
    package.loaded['codex.prompt'] = nil
    package.loaded['codex.state'] = nil
    package.loaded['codex.terminal'] = nil

    local stale_dir = '/tmp/codex-nvim-stale-terminal-cwd'
    local app_dir = '/tmp/codex-nvim-current-app-cwd'
    vim.fn.mkdir(stale_dir, 'p')
    vim.fn.mkdir(app_dir, 'p')

    local received_cmd
    local received_opts
    local stopped_job
    vim.fn = setmetatable({
      executable = function()
        return 1
      end,
      jobstop = function(job)
        stopped_job = job
      end,
      termopen = function(cmd, opts)
        received_cmd = cmd
        received_opts = opts
        return 6201
      end,
    }, { __index = original_fn })

    require('codex').setup {
      backend = 'app_server',
      cmd = 'codex',
      autoinstall = false,
      keymaps = {},
      app_server = {
        ui = 'terminal',
        open_terminal = true,
      },
    }

    local state = require 'codex.state'
    local terminal = require 'codex.terminal'
    local app_server = require 'codex.app_server'
    local session = state.create_session()
    terminal.open_placeholder { cwd = stale_dir, session = session }
    session.job = 6199
    state.sync_active_session()
    state.app.listen_url = 'ws://127.0.0.1:45555'
    state.app.cwd = app_dir

    app_server.open_terminal { session = session }

    eq(6199, stopped_job)
    assert(received_cmd, 'remote terminal should launch')
    assert(vim.tbl_contains(received_cmd, '--remote'), 'remote TUI should connect to the app-server')
    assert(vim.tbl_contains(received_cmd, '--cd'), 'remote TUI should receive an explicit cwd')
    assert(not vim.tbl_contains(received_cmd, '--all'), 'remote TUI should not force all-session resume mode')
    eq(app_dir, received_cmd[#received_cmd])
    eq(app_dir, received_opts.cwd)
  end)
end)
