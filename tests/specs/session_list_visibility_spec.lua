-- luacheck: globals describe it assert eq before_each after_each

local eq = assert.equals

describe('session side panel visibility', function()
  local original_fn

  before_each(function()
    original_fn = vim.fn
    local next_job = 900
    vim.fn = setmetatable({
      executable = function()
        return 1
      end,
      termopen = function()
        next_job = next_job + 1
        return next_job
      end,
    }, { __index = original_fn })
    for _, module in ipairs { 'codex', 'codex.app_server', 'codex.commands', 'codex.config', 'codex.state', 'codex.terminal', 'codex.ui', 'codex.session_list' } do
      package.loaded[module] = nil
    end
    vim.cmd 'silent! only!'
    vim.cmd 'enew'
    require('codex').setup { backend = 'terminal', autoinstall = false, panel = false }
  end)

  after_each(function()
    vim.fn = original_fn
    pcall(require('codex').close)
  end)

  it('hides the session list while there is only one session', function()
    require('codex.terminal').open { focus = false }
    eq(1, #require('codex.state').session_order)
    eq(false, require('codex.session_list').is_open())
  end)

  it('shows the session list once there are two sessions', function()
    require('codex.terminal').open { focus = false }
    require('codex.terminal').new_session { focus = false }
    eq(2, #require('codex.state').session_order)
    eq(true, require('codex.session_list').is_open())
  end)
end)
