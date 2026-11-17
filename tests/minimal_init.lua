vim.cmd 'set rtp+=.'

-- plenary.nvim: $PLENARY_DIR (set by CI and `make test-*`), then the usual install locations.
local function find_plenary()
  local candidates = {
    os.getenv 'PLENARY_DIR',
    vim.fn.stdpath 'data' .. '/site/pack/test/start/plenary.nvim',
    vim.fn.stdpath 'data' .. '/site/pack/deps/start/plenary.nvim',
    vim.fn.stdpath 'data' .. '/lazy/plenary.nvim',
    './plenary.nvim',
  }
  for _, dir in ipairs(candidates) do
    if dir and dir ~= '' and vim.fn.isdirectory(dir .. '/lua/plenary') == 1 then
      return dir
    end
  end
  error 'plenary.nvim not found: set PLENARY_DIR or install it under site/pack/test/start'
end

vim.opt.runtimepath:append(find_plenary())
vim.opt.runtimepath:append(vim.fn.getcwd())
pcall(require, 'plugin.codex')
