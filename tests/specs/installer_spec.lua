local os_module = os -- a local alias: luacheck reports assigning to the os global
describe('codex.nvim cold start installer flow', function()
  local orig_execute

  before_each(function()
    -- Same as installer_matrix_spec: no real corepack calls on the machine running the suite.
    orig_execute = os_module.execute
    os_module.execute = function()
      return 0
    end
    vim.cmd 'set noswapfile'

    -- Mock termopen to simulate successful install
    vim.fn.termopen = function(cmd, opts)
      if type(cmd) == 'string' and type(opts.on_exit) == 'function' then
        vim.defer_fn(function()
          opts.on_exit(0)
        end, 10)
      end
      return 42 -- fake job id
    end

    -- Stub UI select to simulate choosing npm
    vim.ui.select = function(_items, _, on_choice)
      on_choice 'npm'
    end
  end)

  it('installs via selected PM and opens the window', function()
    local codex = require 'codex'
    codex.setup {
      backend = 'terminal',
      cmd = 'codex',
      autoinstall = true,
    }

    codex.open()

    vim.wait(1000, function()
      return require('codex.state').job == nil and require('codex.state').win ~= nil
    end, 10)

    local win = require('codex.state').win
    assert(win and vim.api.nvim_win_is_valid(win), 'Codex window should be open after install')

    codex.close()
    assert(not vim.api.nvim_win_is_valid(win), 'Codex window should be closed')
  end)
  after_each(function()
    os_module.execute = orig_execute
  end)
end)
