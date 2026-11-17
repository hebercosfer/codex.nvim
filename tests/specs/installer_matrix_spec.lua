local eq = assert.equals
local os_module = os -- a local alias: luacheck reports assigning to the os global

describe('codex.nvim multi-installer matrix flow', function()
  local orig_execute

  before_each(function()
    -- detect_available_package_managers runs `corepack enable` for real; keep the test from
    -- changing the machine (or waiting on corepack's prompts) on a CI runner.
    orig_execute = os_module.execute
    os_module.execute = function()
      return 0
    end
    vim.cmd 'set noswapfile'
    vim.cmd 'silent! bwipeout!'

    -- Capture notify messages for assertions
    _G.__codex_notify_log = {}
    vim.notify = function(msg, level)
      table.insert(_G.__codex_notify_log, { msg = msg, level = level })
      print('[notify]', msg)
    end

    -- Fake termopen for simulating install results
    vim.fn.termopen = function(cmd, opts)
      local success = cmd:match 'npm' or cmd:match 'pnpm' or cmd:match 'yarn' or cmd:match 'bun' or cmd:match 'deno'
      local code = success and 0 or 1
      vim.defer_fn(function()
        if opts.on_exit then
          opts.on_exit(1234, code) -- job_id, exit_code
        end
      end, 10)
      return 1234
    end
  end)

  it('tries each supported PM and handles success/failure gracefully', function()
    local installer = require 'codex.installer'
    local state = require 'codex.state'
    local available = installer.detect_available_package_managers()
    assert(#available > 0, 'No package managers available for test')

    local success_pms = {
      npm = true,
      pnpm = true,
      yarn = true,
      bun = true,
      deno = true,
    }

    for _, pm in ipairs(available) do
      local triggered = false

      installer.run_install(pm, function()
        triggered = true
        local win = state.win
        assert(win and vim.api.nvim_win_is_valid(win), 'Codex float should open on success')
        vim.api.nvim_win_close(win, true)
        state.win = nil
      end)

      vim.wait(500, function()
        return state.job == nil
      end)

      local found_notice = false
      for _, entry in ipairs(_G.__codex_notify_log) do
        if entry.msg:match 'Installation failed' and entry.msg:match(pm) then
          found_notice = true
          break
        end
      end

      eq(success_pms[pm] == true, triggered)

      if not success_pms[pm] then
        assert(found_notice, 'Failure should notify for ' .. pm)
      else
        assert(not found_notice, 'Should not show failure notice for successful PM: ' .. pm)
      end
    end
  end)
  after_each(function()
    os_module.execute = orig_execute
  end)
end)
