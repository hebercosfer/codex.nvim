local M = {
  name = 'openDiff',
  description = 'Open a Neovim diff for proposed file contents and ask whether to apply them',
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

local function split_contents(contents)
  local lines = vim.split(contents, '\n', { plain = true })
  local endofline = contents:sub(-1) == '\n'
  if endofline then
    table.remove(lines)
  end
  if #lines == 0 then
    lines = { '' }
  end
  return lines, endofline
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

local function refresh_buffer(buf, path, contents)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' or vim.fn.fnamemodify(name, ':p') ~= vim.fn.fnamemodify(path, ':p') then
    return nil
  end

  local lines, endofline = split_contents(contents)
  local was_modifiable = vim.api.nvim_buf_get_option(buf, 'modifiable')
  local ok, err = pcall(function()
    if not was_modifiable then
      vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
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

  local original_win = vim.api.nvim_get_current_win()
  local original_buf
  local proposal_win
  local proposal_buf

  local function cleanup()
    for _, win in ipairs { original_win, proposal_win } do
      if win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_call, win, function()
          vim.cmd 'diffoff'
        end)
      end
    end
    if proposal_win and vim.api.nvim_win_is_valid(proposal_win) then
      pcall(vim.api.nvim_win_close, proposal_win, true)
    end
    if proposal_buf and vim.api.nvim_buf_is_valid(proposal_buf) then
      pcall(vim.api.nvim_buf_delete, proposal_buf, { force = true })
    end
    pcall(vim.fn.delete, temp)
    if original_win and vim.api.nvim_win_is_valid(original_win) then
      pcall(vim.api.nvim_set_current_win, original_win)
    end
  end

  local opened, open_err = pcall(function()
    vim.cmd('edit ' .. vim.fn.fnameescape(old_path))
    original_buf = vim.api.nvim_get_current_buf()
    vim.cmd 'diffthis'
    vim.cmd('rightbelow vsplit ' .. vim.fn.fnameescape(temp))
    proposal_win = vim.api.nvim_get_current_win()
    proposal_buf = vim.api.nvim_get_current_buf()
    vim.cmd 'diffthis'
    vim.api.nvim_buf_set_name(proposal_buf, params.tab_name)
  end)
  if not opened then
    cleanup()
    error(open_err)
  end

  local selected, select_err = pcall(vim.ui.select, { 'Accept', 'Reject' }, { prompt = 'Apply Codex diff?' }, function(choice)
    if choice == 'Accept' then
      local saved, save_err = write_contents(new_path, params.new_file_contents)
      if not saved then
        cleanup()
        done('Could not save accepted diff to ' .. new_path .. ': ' .. tostring(save_err), false)
        return
      end
      local refreshed, refresh_err = refresh_destination(new_path, params.new_file_contents, original_buf)
      cleanup()
      if not refreshed then
        done('Saved accepted diff but could not refresh the open buffer: ' .. tostring(refresh_err), false)
        return
      end
      done({ result = 'FILE_SAVED', filePath = new_path }, true)
    else
      cleanup()
      done({ result = 'DIFF_REJECTED', filePath = new_path }, true)
    end
  end)
  if not selected then
    cleanup()
    error(select_err)
  end

  return { __codex_deferred = true }
end

return M
