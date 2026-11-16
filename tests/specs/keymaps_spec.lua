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
  local lhs_list = { '<leader>xc', '<leader>xs', '<leader>cc', '<leader>cC', '<leader>cn', '<leader>cy', '<leader>cs', '<leader>aC', '<leader>as' }

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
      pcall(vim.keymap.del, { 'n', 't', 'v' }, lhs)
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
  end)
end)
