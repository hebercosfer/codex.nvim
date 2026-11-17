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

-- Coverage. Plenary runs each spec file in a child Neovim, so the recording has to start in
-- every child that loads this file, not only in the runner. Set CODEX_LUACOV=1 (make coverage does).
-- Only the per-spec children record: plenary starts each one with plenary.busted in its command
-- line. The runner process also loads this file, and if it recorded too, its exit would overwrite
-- the stats the children merged, so the totals would depend on timing.
local function is_spec_child()
  for _, arg in ipairs(vim.v.argv) do
    if arg:find('plenary.busted', 1, true) then
      return true
    end
  end
  return false
end

if os.getenv 'CODEX_LUACOV' and is_spec_child() then
  local ok, runner = pcall(require, 'luacov.runner')
  if ok then
    runner.init { statsfile = 'luacov.stats.out', tick = true }
    vim.api.nvim_create_autocmd('VimLeavePre', {
      callback = function()
        runner.shutdown()
      end,
    })
  end
end
