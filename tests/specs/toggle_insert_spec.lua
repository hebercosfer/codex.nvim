-- luacheck: globals describe it assert eq before_each after_each

local eq = assert.equals

describe('toggle opens straight into insert mode', function()
  local original_fn
  local original_cmd

  before_each(function()
    original_fn = vim.fn
    original_cmd = vim.cmd
    for _, module in ipairs { 'codex', 'codex.app_server', 'codex.commands', 'codex.config', 'codex.state', 'codex.terminal', 'codex.ui' } do
      package.loaded[module] = nil
    end
    vim.cmd 'silent! only!'
    vim.cmd 'enew'
  end)

  after_each(function()
    vim.cmd = original_cmd
    vim.fn = original_fn
    pcall(require('codex').close)
  end)

  -- Neovim only switches to insert mode once the command loop resumes, which a
  -- headless spec never does, so record the startinsert request instead.
  local function record_startinsert()
    local requested = false
    local cmd_fn = original_cmd
    vim.cmd = setmetatable({}, {
      __call = function(_, command, ...)
        if command == 'startinsert' then
          requested = true
        end
        return cmd_fn(command, ...)
      end,
      __index = function(_, key)
        return cmd_fn[key]
      end,
    })
    return function()
      return requested
    end
  end

  local function setup_app_server(received)
    vim.fn = setmetatable({
      executable = function()
        return 1
      end,
      termopen = function(cmd)
        table.insert(received, cmd)
        return 900 + #received
      end,
    }, { __index = original_fn })

    require('codex').setup {
      backend = 'app_server',
      autoinstall = false,
      panel = false,
      app_server = { ui = 'terminal', auto_start = false },
    }
    local state = require 'codex.state'
    require('codex.app_server').start = function(callback)
      state.app.listen_url = 'ws://127.0.0.1:45556'
      callback(true)
    end
  end

  it('requests insert mode when the app-server terminal toggle opens the window', function()
    local received = {}
    setup_app_server(received)
    local was_requested = record_startinsert()

    require('codex').toggle()
    vim.wait(1000, function()
      return #received == 1
    end, 10)

    eq(1, #received)
    assert(was_requested(), 'toggle should request insert mode when it opens the Codex window')
  end)

  it('does not request insert mode when the window is closed by the toggle', function()
    local received = {}
    setup_app_server(received)
    require('codex').toggle()
    vim.wait(1000, function()
      return #received == 1
    end, 10)

    local was_requested = record_startinsert()
    require('codex').toggle()
    assert(not was_requested(), 'closing the window should not enter insert mode')
  end)
end)
