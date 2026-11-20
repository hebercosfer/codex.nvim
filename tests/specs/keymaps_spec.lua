-- luacheck: globals describe it assert eq before_each after_each

local eq = assert.equals

local function fresh_config()
  package.loaded['codex.config'] = nil
  return require 'codex.config'
end

describe('keymaps configuration', function()
  before_each(function()
    fresh_config()
  end)

  it('defaults every leader mapping under the <leader>c prefix', function()
    local keymaps = fresh_config().defaults.keymaps
    eq('<leader>cc', keymaps.toggle)
    eq('<leader>cC', keymaps.open)
    eq('<leader>cn', keymaps.session_new)
    eq('<leader>cy', keymaps.yolo)
    eq('<leader>cs', keymaps.send)
    eq('<leader>ca', keymaps.diff_accept)
    eq('<leader>cd', keymaps.diff_reject)
  end)

  it('keeps the defaults when keymaps is omitted', function()
    local config = fresh_config()
    eq(true, vim.deep_equal(config.defaults.keymaps, config.apply({}).keymaps))
    eq(true, vim.deep_equal(config.defaults.keymaps, config.apply(nil).keymaps))
  end)

  it('overrides only the configured keymaps and keeps the other defaults', function()
    local config = fresh_config()
    local keymaps = config.apply({ keymaps = { toggle = '<leader>xc' } }).keymaps
    eq('<leader>xc', keymaps.toggle)
    eq(config.defaults.keymaps.open, keymaps.open)
    eq(config.defaults.keymaps.send, keymaps.send)
    eq(config.defaults.keymaps.quit, keymaps.quit)
  end)

  it('keeps every default when the keymaps table is empty', function()
    local config = fresh_config()
    eq(true, vim.deep_equal(config.defaults.keymaps, config.apply({ keymaps = {} }).keymaps))
  end)

  it('maps nothing when keymaps is false', function()
    local keymaps = fresh_config().apply({ keymaps = false }).keymaps
    eq(true, vim.deep_equal({}, keymaps))
  end)

  it('treats an empty string as a skipped mapping', function()
    local keymaps = fresh_config().apply({ keymaps = { toggle = '', send = '<leader>xs' } }).keymaps
    eq(false, keymaps.toggle)
    eq('<leader>xs', keymaps.send)
  end)

  it('rejects non-string keymap values', function()
    local config = fresh_config()
    local ok = pcall(config.apply, { keymaps = { toggle = 42 } })
    eq(false, ok)
  end)

  it('does not modify the defaults when the user overrides them', function()
    local config = fresh_config()
    config.apply { keymaps = { toggle = '<leader>xc' } }
    eq('<leader>cc', config.defaults.keymaps.toggle)
  end)
end)

describe('keymaps setup', function()
  local lhs_list = { '<leader>xc', '<leader>xs', '<leader>cc', '<leader>cC', '<leader>cn', '<leader>cy', '<leader>cs', '<leader>ca', '<leader>cd', '<leader>aC', '<leader>as' }

  -- plugin/codex.lua installs the defaults when the plugin loads, and setup_with reloads
  -- the module, which forgets what the old instance mapped. Clear them so every test starts clean.
  before_each(function()
    for _, lhs in ipairs(lhs_list) do
      pcall(vim.keymap.del, { 'n', 't', 'v', 'x' }, lhs)
    end
  end)

  local function setup_with(keymaps)
    for _, module in ipairs { 'codex', 'codex.app_server', 'codex.commands', 'codex.config', 'codex.state', 'codex.terminal', 'codex.ui' } do
      package.loaded[module] = nil
    end
    require('codex').setup {
      backend = 'app_server',
      autoinstall = false,
      panel = false,
      keymaps = keymaps,
      app_server = { ui = 'terminal', auto_start = false },
    }
  end

  local function mapped(lhs)
    return vim.fn.maparg(lhs, 'n') ~= ''
  end

  after_each(function()
    for _, lhs in ipairs(lhs_list) do
      pcall(vim.keymap.del, { 'n', 't', 'v', 'x' }, lhs)
    end
  end)

  it('maps configured keys over the defaults and leaves the rest of the defaults in place', function()
    setup_with { toggle = '<leader>xc', send = '<leader>xs' }
    assert(mapped '<leader>xc', 'configured toggle should be mapped')
    assert(mapped '<leader>xs', 'configured send should be mapped')
    assert(not mapped '<leader>cc', 'default toggle should be replaced by the configured one')
    assert(not mapped '<leader>cs', 'default send should be replaced by the configured one')
    assert(mapped '<leader>cC', 'default open should stay mapped when only toggle and send are configured')
    assert(not mapped '<leader>aC', 'legacy <leader>a mappings should not be mapped')
  end)

  it('maps diff decisions by default without changing the new-session key', function()
    setup_with(nil)
    assert(mapped '<leader>cc', 'normal <leader>cc should still toggle Codex')
    assert(vim.fn.maparg('<leader>cc', 'x') == '', 'visual <leader>cc should remain available to user config')
    assert(mapped '<leader>cn', '<leader>cn should remain available for a new session')
    assert(mapped '<leader>ca', '<leader>ca should accept a diff')
    assert(mapped '<leader>cd', '<leader>cd should reject a diff')
  end)

  it('does not leave an overridden default behind after a later setup call on the same module', function()
    -- Mirrors plugin/codex.lua's default setup on load, followed by the user's setup().
    setup_with(nil)
    assert(mapped '<leader>cc', 'default toggle should be mapped by the first setup')

    require('codex').setup {
      backend = 'app_server',
      autoinstall = false,
      panel = false,
      keymaps = { toggle = '<leader>xc' },
      app_server = { ui = 'terminal', auto_start = false },
    }
    assert(not mapped '<leader>cc', 'overridden default toggle should be removed by the later setup')
    assert(mapped '<leader>cs', 'un-overridden default send should still be mapped')
    assert(mapped '<leader>xc', 'configured toggle should be mapped by the later setup')
  end)

  it('installs no leader mappings when keymaps is false', function()
    setup_with(false)
    for _, lhs in ipairs(lhs_list) do
      assert(not mapped(lhs), lhs .. ' should not be mapped when keymaps = false')
    end
    assert(vim.fn.maparg('<leader>cc', 'x') == '', 'visual <leader>cc should not be mapped by the plugin')
  end)
end)

describe('codex window keymaps', function()
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
    for _, module in ipairs { 'codex', 'codex.app_server', 'codex.commands', 'codex.config', 'codex.state', 'codex.terminal', 'codex.ui' } do
      package.loaded[module] = nil
    end
    vim.cmd 'silent! only!'
    vim.cmd 'enew'
  end)

  after_each(function()
    vim.fn = original_fn
    pcall(require('codex').close)
  end)

  it('keeps leader mappings out of terminal mode', function()
    require('codex').setup { backend = 'terminal', autoinstall = false, panel = false, keymaps = { toggle = '<leader>xc' } }
    assert(vim.fn.maparg('<leader>xc', 't') == '', 'toggle should not be mapped in terminal mode')
  end)

  it('disables leader mappings inside the Codex window but keeps <C-q> to leave', function()
    require('codex').setup { backend = 'terminal', autoinstall = false, panel = false }
    vim.cmd 'CodexToggle'
    local buf = vim.api.nvim_get_current_buf()
    local nop, quit = 0, false
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if map.rhs == '' or map.rhs == '<Nop>' then -- neovim reports <Nop> as an empty rhs
        nop = nop + 1
      elseif map.rhs:find('close()', 1, true) then
        quit = true
      end
    end
    -- toggle, open, send, session_new and yolo are all disabled in the Codex window.
    eq(5, nop)
    assert(quit, '<C-q> should stay mapped to close the Codex window')
  end)
end)
