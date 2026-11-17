-- luacheck: globals describe it assert eq before_each after_each

-- These drive the plugin the way a user does: they press keys and check what is on screen.
-- A failure here is a user-visible bug, so nothing in this file is skipped.

local eq = assert.equals

-- Required on each use: before_each reloads codex.state, so a reference captured here goes stale.
local function state()
  return require 'codex.state'
end

local function keys(sequence)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(sequence, true, false, true), 'mx', false)
end

local function codex_window_open()
  local win = state().win
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

describe('user flows', function()
  local original_fn

  before_each(function()
    original_fn = vim.fn
    vim.fn = setmetatable({
      executable = function()
        return 1
      end,
      termopen = function()
        return 901
      end,
    }, { __index = original_fn })
    for _, module in ipairs { 'codex', 'codex.app_server', 'codex.commands', 'codex.config', 'codex.state', 'codex.terminal', 'codex.ui', 'codex.session_list' } do
      package.loaded[module] = nil
    end
    vim.cmd 'silent! only!'
    vim.cmd 'enew'
  end)

  after_each(function()
    pcall(require('codex').close)
    vim.fn = original_fn
  end)

  it('opens the Codex window when the toggle key is pressed from a normal buffer', function()
    require('codex').setup { backend = 'terminal', autoinstall = false, panel = false, keymaps = { toggle = '<leader>xc' } }
    eq(false, codex_window_open())

    keys '\\xc'

    assert(vim.wait(1000, codex_window_open, 10), 'pressing the toggle key should open the Codex window')
    eq(state().win, vim.api.nvim_get_current_win())
  end)

  it('closes the Codex window with the configured quit key', function()
    require('codex').setup { backend = 'terminal', autoinstall = false, panel = false, keymaps = { quit = '<C-x><CR>' } }
    require('codex').open()
    assert(vim.wait(1000, codex_window_open, 10), 'the Codex window should be open before pressing quit')

    keys '<C-x><CR>'

    assert(
      vim.wait(1000, function()
        return not codex_window_open()
      end, 10),
      'the quit key should close the Codex window'
    )
  end)

  it('ignores the leader toggle inside the Codex window, so it cannot close it', function()
    require('codex').setup { backend = 'terminal', autoinstall = false, panel = false, keymaps = { toggle = '<leader>xc' } }
    require('codex').open()
    assert(vim.wait(1000, codex_window_open, 10), 'the Codex window should be open')

    keys '\\xc'
    vim.wait(100, function()
      return false
    end, 10)

    assert(codex_window_open(), 'pressing the toggle key inside the Codex window must not close it')
  end)
end)
