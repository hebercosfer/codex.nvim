local eq = assert.equals
local same = assert.same
local open_diff = require 'codex.tools.open_diff'

describe('openDiff review cleanup', function()
  local original_tabs
  local original_buffers
  local temp_paths
  local codex
  local codex_state
  local original_codex_methods
  local original_state_win

  before_each(function()
    original_tabs = {}
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      original_tabs[tab] = true
    end
    original_buffers = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      original_buffers[buf] = true
    end
    temp_paths = {}

    codex = require 'codex'
    codex_state = require 'codex.state'
    original_codex_methods = {
      open = codex.open,
      close = codex.close,
      focus = codex.focus,
    }
    original_state_win = codex_state.win
  end)

  after_each(function()
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if not original_tabs[tab] then
        pcall(vim.api.nvim_set_current_tabpage, tab)
        pcall(vim.cmd, 'tabclose!')
      end
    end
    if codex_state then
      local win = codex_state.win
      if win and win ~= original_state_win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
      codex_state.win = original_state_win
    end
    if codex and original_codex_methods then
      codex.open = original_codex_methods.open
      codex.close = original_codex_methods.close
      codex.focus = original_codex_methods.focus
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if not original_buffers[buf] and vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    for tab in pairs(original_tabs) do
      if vim.api.nvim_tabpage_is_valid(tab) then
        pcall(vim.api.nvim_set_current_tabpage, tab)
      end
    end
    for _, path in ipairs(temp_paths) do
      vim.fn.delete(path)
    end
    pcall(vim.api.nvim_del_user_command, 'CodexDiffReject')
  end)

  local function open_review(proposal)
    local path = vim.fn.tempname()
    temp_paths[#temp_paths + 1] = path
    vim.fn.writefile({ 'original' }, path)

    local completed, result, success = false, nil, nil
    open_diff.handler({
      old_file_path = path,
      new_file_path = path,
      new_file_contents = proposal .. '\n',
      tab_name = 'openDiff cleanup test',
    }, function(value, ok)
      completed, result, success = true, value, ok
    end)

    return path, vim.api.nvim_get_current_tabpage(), function()
      assert(vim.wait(1000, function()
        return completed
      end), 'openDiff should complete its deferred response')
      return result, success
    end
  end

  local function install_focus_spy()
    local requested = false
    local function create_float()
      local buf = vim.api.nvim_create_buf(false, true)
      return vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = 20,
        height = 3,
        row = 0,
        col = 0,
        style = 'minimal',
      })
    end

    local initial_win = create_float()
    codex_state.win = initial_win
    codex.close = function()
      pcall(vim.api.nvim_win_close, initial_win, true)
      codex_state.win = nil
    end
    codex.open = function()
      error('openDiff restoration should use codex.focus')
    end
    codex.focus = function()
      requested = true
      codex_state.win = create_float()
    end
    return function()
      return requested
    end
  end

  it('closes the temporary diff tab and focuses Codex after saving', function()
    local was_focused = install_focus_spy()
    local before_tabs = #vim.api.nvim_list_tabpages()
    local before_windows = #vim.api.nvim_list_wins()
    local path, diff_tab, wait_for_result = open_review('accepted')

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'accepted' })
    vim.api.nvim_buf_set_option(0, 'modified', true)
    vim.cmd 'write'

    local result, success = wait_for_result()
    eq(true, success)
    eq('FILE_SAVED', result.result)
    same({ 'accepted' }, vim.fn.readfile(path))
    eq(false, vim.api.nvim_tabpage_is_valid(diff_tab))
    eq(before_tabs, #vim.api.nvim_list_tabpages())
    eq(before_windows, #vim.api.nvim_list_wins())
    assert(was_focused(), 'accepting should focus the Codex window')
    eq(codex_state.win, vim.api.nvim_get_current_win())
  end)

  it('closes the temporary diff tab and focuses Codex after rejecting', function()
    local was_focused = install_focus_spy()
    local before_tabs = #vim.api.nvim_list_tabpages()
    local before_windows = #vim.api.nvim_list_wins()
    local path, diff_tab, wait_for_result = open_review('rejected')

    assert(open_diff.reject_current_diff())

    local result, success = wait_for_result()
    eq(true, success)
    eq('DIFF_REJECTED', result.result)
    same({ 'original' }, vim.fn.readfile(path))
    eq(false, vim.api.nvim_tabpage_is_valid(diff_tab))
    eq(before_tabs, #vim.api.nvim_list_tabpages())
    eq(before_windows, #vim.api.nvim_list_wins())
    assert(was_focused(), 'rejecting should focus the Codex window')
    eq(codex_state.win, vim.api.nvim_get_current_win())
  end)

  it('maps :cq on the proposal buffer to rejection instead of quitting Neovim', function()
    local before_tabs = #vim.api.nvim_list_tabpages()
    local path, diff_tab, wait_for_result = open_review('rejected')

    pcall(vim.api.nvim_del_user_command, 'CodexDiffReject')
    vim.api.nvim_create_user_command('CodexDiffReject', function()
      open_diff.reject_current_diff()
    end, {})

    local abbreviations = vim.fn.execute('cabbrev <buffer>')
    assert(abbreviations:find('cq', 1, true), 'proposal buffer should define a :cq abbreviation')
    assert(abbreviations:find('CodexDiffReject', 1, true), 'the :cq abbreviation should reject the proposal')

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(':cq<CR>', true, false, true), 'xt', false)
    local result, success = wait_for_result()
    eq(true, success)
    eq('DIFF_REJECTED', result.result)
    same({ 'original' }, vim.fn.readfile(path))
    eq(false, vim.api.nvim_tabpage_is_valid(diff_tab))
    eq(before_tabs, #vim.api.nvim_list_tabpages())
  end)
end)
