local state = require 'codex.state'

local M = {
  name = 'openDiff',
  description = 'Open a native Neovim diff for a proposal; save to accept or close to reject',
  input_schema = {
    type = 'object',
    properties = {
      old_file_path = { type = 'string', description = 'Path to the original file' },
      new_file_path = { type = 'string', description = 'Path to write if accepted' },
      new_file_contents = { type = 'string', description = 'Proposed file contents' },
      tab_name = { type = 'string', description = 'Name for the diff view' },
    },
    required = { 'old_file_path', 'new_file_path', 'new_file_contents', 'tab_name' },
    additionalProperties = false,
  },
}

local pending_by_buf = {}
local autocmd_group
local exit_autocmd

local function group()
  if not autocmd_group then
    autocmd_group = vim.api.nvim_create_augroup('CodexOpenDiff', { clear = false })
  end
  return autocmd_group
end

local function split_contents(contents)
  local fileformat = 'unix'
  if contents:find('\r\n', 1, true) then
    contents = contents:gsub('\r\n', '\n')
    fileformat = 'dos'
  elseif contents:find('\r', 1, true) then
    contents = contents:gsub('\r', '\n')
    fileformat = 'mac'
  end

  local lines = vim.split(contents, '\n', { plain = true })
  local endofline = contents:sub(-1) == '\n'
  if endofline then
    table.remove(lines)
  end
  if #lines == 0 then
    lines = { '' }
  end
  return lines, endofline, fileformat
end

local function write_contents(path, contents)
  local ok, result = pcall(vim.fn.writefile, vim.split(contents, '\n', { plain = true }), path, 'b')
  if not ok then
    return false, result
  end
  if result ~= 0 then
    return false, vim.v.errmsg ~= '' and vim.v.errmsg or ('writefile returned ' .. tostring(result))
  end
  return true
end

local function buffer_contents(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local fileformat = vim.api.nvim_buf_get_option(buf, 'fileformat')
  local linebreak = fileformat == 'dos' and '\r\n' or (fileformat == 'mac' and '\r' or '\n')
  local contents = table.concat(lines, linebreak)
  if contents ~= '' and vim.api.nvim_buf_get_option(buf, 'endofline') then
    contents = contents .. linebreak
  end
  return contents
end

local function refresh_buffer(buf, path, contents)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' or vim.fn.fnamemodify(name, ':p') ~= vim.fn.fnamemodify(path, ':p') then
    return nil
  end
  if vim.api.nvim_buf_get_option(buf, 'modified') then
    return nil
  end

  local lines, endofline, fileformat = split_contents(contents)
  local was_modifiable = vim.api.nvim_buf_get_option(buf, 'modifiable')
  local ok, err = pcall(function()
    if not was_modifiable then
      vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, 'fileformat', fileformat)
    vim.api.nvim_buf_set_option(buf, 'endofline', endofline)
    vim.api.nvim_buf_set_option(buf, 'modified', false)
    if not was_modifiable then
      vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    end
  end)
  if not was_modifiable then
    pcall(vim.api.nvim_buf_set_option, buf, 'modifiable', false)
  end
  if not ok then
    return false, err
  end
  return true
end

local function refresh_destination(path, contents, original_buf)
  local refreshed, err = refresh_buffer(original_buf, path, contents)
  if refreshed ~= nil then
    return refreshed, err
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= original_buf then
      refreshed, err = refresh_buffer(buf, path, contents)
      if refreshed ~= nil then
        return refreshed, err
      end
    end
  end
  return true
end

local function is_exiting()
  local exiting = vim.v.exiting
  return type(exiting) == 'number' and exiting ~= 0
end

local function hide_codex_float()
  local win = state.win
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local config = vim.api.nvim_win_get_config(win)
  if not config.relative or config.relative == '' or vim.api.nvim_win_get_tabpage(win) ~= vim.api.nvim_get_current_tabpage() then
    return false
  end

  local ok, codex = pcall(require, 'codex')
  if not ok or type(codex.close) ~= 'function' then
    return false
  end
  local closed = pcall(codex.close)
  return closed and not vim.api.nvim_win_is_valid(win)
end

local function restore_codex_float(hidden)
  if not hidden or is_exiting() then
    return
  end

  local ok, codex = pcall(require, 'codex')
  if not ok then
    return
  end
  if type(codex.focus) == 'function' then
    pcall(codex.focus)
  elseif type(codex.open) == 'function' then
    pcall(codex.open, { focus = true, insert = true })
  end
end

local function cleanup(data)
  if data.cleaned then
    return
  end
  data.cleaned = true

  for _, id in ipairs(data.autocmd_ids or {}) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  if data.proposal_buf and pending_by_buf[data.proposal_buf] == data then
    pending_by_buf[data.proposal_buf] = nil
  end

  pcall(vim.fn.delete, data.temp)

  if not is_exiting() then
    for _, win in ipairs { data.original_file_win, data.proposal_win } do
      if win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_call, win, function()
          vim.cmd 'diffoff'
        end)
      end
    end

    local diff_tab_closed = false
    local diff_tab = data.diff_tab
    if diff_tab and vim.api.nvim_tabpage_is_valid(diff_tab) and diff_tab ~= data.original_tab then
      local selected = pcall(vim.api.nvim_set_current_tabpage, diff_tab)
      if selected then
        if vim.api.nvim_tabpage_close then
          pcall(vim.api.nvim_tabpage_close, diff_tab, true)
          diff_tab_closed = not vim.api.nvim_tabpage_is_valid(diff_tab)
        end

        if not diff_tab_closed and vim.api.nvim_tabpage_is_valid(diff_tab) then
          local ok, windows = pcall(vim.api.nvim_tabpage_list_wins, diff_tab)
          if ok then
            for _, win in ipairs(windows) do
              if vim.api.nvim_win_is_valid(win) then
                pcall(vim.api.nvim_win_close, win, true)
              end
            end
          end
          diff_tab_closed = not vim.api.nvim_tabpage_is_valid(diff_tab)
        end

        if not diff_tab_closed and vim.api.nvim_tabpage_is_valid(diff_tab) then
          pcall(vim.cmd, 'tabclose!')
          diff_tab_closed = not vim.api.nvim_tabpage_is_valid(diff_tab)
        end
      end
      if not diff_tab_closed then
        vim.notify('Could not close the Codex diff tab', vim.log.levels.WARN)
      end
    end

    if not diff_tab_closed and data.proposal_win and vim.api.nvim_win_is_valid(data.proposal_win) then
      pcall(vim.api.nvim_win_close, data.proposal_win, true)
    end
    if data.proposal_buf and vim.api.nvim_buf_is_valid(data.proposal_buf) then
      pcall(vim.api.nvim_buf_delete, data.proposal_buf, { force = true })
    end
    if data.original_tab and vim.api.nvim_tabpage_is_valid(data.original_tab) then
      pcall(vim.api.nvim_set_current_tabpage, data.original_tab)
    end
    if data.original_win and vim.api.nvim_win_is_valid(data.original_win) then
      pcall(vim.api.nvim_set_current_win, data.original_win)
    end
    restore_codex_float(data.hidden_float)
  end
end

local function reply(data, value, success)
  local done = data.done
  data.done = nil
  if done then
    done(value, success)
  end
end

local function reject_diff(data)
  if data.status ~= 'pending' then
    return false
  end
  data.status = 'rejected'
  cleanup(data)
  reply(data, { result = 'DIFF_REJECTED', filePath = data.new_path }, true)
  return true
end

local function accept_diff(data, defer_cleanup)
  if data.status ~= 'pending' then
    return false
  end

  local contents = buffer_contents(data.proposal_buf)
  local saved, save_err = write_contents(data.new_path, contents)
  if not saved then
    vim.notify('Could not save accepted diff to ' .. data.new_path .. ': ' .. tostring(save_err), vim.log.levels.ERROR)
    return false
  end

  local refreshed, refresh_err = refresh_destination(data.new_path, contents, data.original_buf)
  if not refreshed then
    vim.notify('Saved accepted diff but could not refresh the open buffer: ' .. tostring(refresh_err), vim.log.levels.WARN)
  end
  pcall(vim.api.nvim_buf_set_option, data.proposal_buf, 'modified', false)
  data.status = 'accepted'

  local function finish()
    cleanup(data)
    reply(data, { result = 'FILE_SAVED', filePath = data.new_path }, true)
  end

  if defer_cleanup then
    vim.schedule(finish)
  else
    finish()
  end
  return true
end

local function schedule_reject(data, require_hidden)
  vim.schedule(function()
    if data.status ~= 'pending' or not data.proposal_buf or not vim.api.nvim_buf_is_valid(data.proposal_buf) then
      return
    end
    if require_hidden and #vim.fn.win_findbuf(data.proposal_buf) > 0 then
      return
    end
    reject_diff(data)
  end)
end

local function register_diff_autocmds(data)
  local buf = data.proposal_buf
  local active_group = group()
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[cnoreabbrev <buffer> <expr> cq getcmdtype() ==# ':' && getcmdline() ==# 'cq' ? 'CodexDiffReject' : 'cq']])
  end)
  data.autocmd_ids = {
    vim.api.nvim_create_autocmd('BufWriteCmd', {
      group = active_group,
      buffer = buf,
      callback = function()
        if accept_diff(data, true) then
          pcall(vim.cmd, 'diffoff')
        end
      end,
    }),
    vim.api.nvim_create_autocmd('BufHidden', {
      group = active_group,
      buffer = buf,
      callback = function()
        schedule_reject(data, true)
      end,
    }),
    vim.api.nvim_create_autocmd({ 'BufDelete', 'BufUnload', 'BufWipeout' }, {
      group = active_group,
      buffer = buf,
      callback = function()
        schedule_reject(data, false)
      end,
    }),
  }
end

local function ensure_exit_autocmd()
  if exit_autocmd then
    return
  end
  exit_autocmd = vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group(),
    callback = function()
      local pending = {}
      for _, data in pairs(pending_by_buf) do
        table.insert(pending, data)
      end
      for _, data in ipairs(pending) do
        reject_diff(data)
      end
    end,
  })
end

function M.accept_current_diff()
  local data = pending_by_buf[vim.api.nvim_get_current_buf()]
  if not data then
    vim.notify('No active Codex diff in the current buffer', vim.log.levels.WARN)
    return false
  end
  return accept_diff(data, false)
end

function M.reject_current_diff()
  local data = pending_by_buf[vim.api.nvim_get_current_buf()]
  if not data then
    vim.notify('No active Codex diff in the current buffer', vim.log.levels.WARN)
    return false
  end
  return reject_diff(data)
end

function M.handler(params, done)
  for _, key in ipairs { 'old_file_path', 'new_file_path', 'new_file_contents', 'tab_name' } do
    if params[key] == nil then
      error('Missing ' .. key)
    end
  end

  local old_path = vim.fn.fnamemodify(vim.fn.expand(params.old_file_path), ':p')
  local new_path = vim.fn.fnamemodify(vim.fn.expand(params.new_file_path), ':p')
  local temp = vim.fn.tempname()
  local wrote_temp, temp_err = write_contents(temp, params.new_file_contents)
  if not wrote_temp then
    pcall(vim.fn.delete, temp)
    error('Could not create diff proposal: ' .. tostring(temp_err))
  end

  local hidden_float = hide_codex_float()
  local data = {
    done = done,
    hidden_float = hidden_float,
    original_tab = vim.api.nvim_get_current_tabpage(),
    original_win = vim.api.nvim_get_current_win(),
    new_path = new_path,
    temp = temp,
    status = 'pending',
  }

  local opened, open_err = pcall(function()
    vim.cmd 'tabnew'
    data.diff_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd('edit ' .. vim.fn.fnameescape(old_path))
    data.original_buf = vim.api.nvim_get_current_buf()
    data.original_file_win = vim.api.nvim_get_current_win()
    vim.cmd 'diffthis'
    vim.cmd('rightbelow vsplit ' .. vim.fn.fnameescape(temp))
    data.proposal_win = vim.api.nvim_get_current_win()
    data.proposal_buf = vim.api.nvim_get_current_buf()
    vim.cmd 'diffthis'
    vim.api.nvim_buf_set_name(data.proposal_buf, params.tab_name .. ' (proposed)')
    vim.api.nvim_buf_set_option(data.proposal_buf, 'buftype', 'acwrite')
    vim.api.nvim_buf_set_option(data.proposal_buf, 'bufhidden', 'hide')
    vim.api.nvim_buf_set_option(data.proposal_buf, 'buflisted', false)
    vim.api.nvim_buf_set_option(data.proposal_buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(data.proposal_buf, 'filetype', vim.api.nvim_buf_get_option(data.original_buf, 'filetype'))
    vim.api.nvim_buf_set_option(data.proposal_buf, 'modified', false)
    pending_by_buf[data.proposal_buf] = data
    register_diff_autocmds(data)
    ensure_exit_autocmd()
  end)
  if not opened then
    data.status = 'failed'
    cleanup(data)
    error(open_err)
  end

  return { __codex_deferred = true }
end

return M
