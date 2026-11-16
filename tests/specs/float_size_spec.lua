-- luacheck: globals describe it assert eq before_each after_each

local eq = assert.equals

describe('codex float size', function()
  local original_fn
  local original_columns, original_lines

  before_each(function()
    original_fn = vim.fn
    original_columns, original_lines = vim.o.columns, vim.o.lines
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
    vim.o.columns, vim.o.lines = original_columns, original_lines
    pcall(require('codex').close)
  end)

  local function float_size(opts)
    require('codex').setup(vim.tbl_extend('force', { backend = 'terminal', autoinstall = false, panel = false }, opts or {}))
    vim.cmd 'CodexToggle'
    local win = require('codex.state').win
    return vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
  end

  it('uses the configured fraction when it is above the minimum', function()
    vim.o.columns, vim.o.lines = 200, 100
    local w, h = float_size { width = 0.5, height = 0.5 }
    eq(100, w)
    eq(50, h)
  end)

  it('grows the float to the minimum size on a small editor', function()
    vim.o.columns, vim.o.lines = 200, 60
    local w, h = float_size { width = 0.2, height = 0.2 }
    eq(80, w)
    eq(24, h)
  end)

  it('caps the minimum at the editor size', function()
    vim.o.columns, vim.o.lines = 50, 20
    local w, h = float_size {}
    -- The rounded border (2 cells each way), the command line and the status line come out of the editor size.
    eq(vim.o.columns - 2, w)
    eq(vim.o.lines - vim.o.cmdheight - 2 - (vim.o.laststatus > 0 and 1 or 0), h)
  end)

  it('uses the configured minimum size', function()
    vim.o.columns, vim.o.lines = 200, 100
    local w, h = float_size { width = 0.1, height = 0.1, min_width = 120, min_height = 40 }
    eq(120, w)
    eq(40, h)
  end)

  local function float_title()
    local title = vim.api.nvim_win_get_config(require('codex.state').win).title
    if type(title) == 'table' then
      return title[1][1], vim.api.nvim_win_get_config(require('codex.state').win).title_pos
    end
    return title, nil
  end

  it('centers the title " Codex " on the float border by default', function()
    vim.o.columns, vim.o.lines = 200, 60
    float_size {}
    local text, pos = float_title()
    eq(' Codex ', text)
    eq('center', pos)
  end)

  it('shows no title when title is false', function()
    vim.o.columns, vim.o.lines = 200, 60
    float_size { title = false }
    local text = float_title()
    assert(text == nil or text == '', 'no title expected, got ' .. vim.inspect(text))
  end)
end)
