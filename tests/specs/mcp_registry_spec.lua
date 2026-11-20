local eq = assert.equals

describe('codex MCP registry', function()
  local original_fn
  local cache_root
  local registry
  local manifest_path

  before_each(function()
    original_fn = vim.fn
    cache_root = original_fn.tempname()
    original_fn.mkdir(cache_root, 'p')
    vim.fn = setmetatable({
      stdpath = function(name)
        if name == 'cache' then
          return cache_root
        end
        return original_fn.stdpath(name)
      end,
    }, { __index = original_fn })
    package.loaded['codex.mcp_registry'] = nil
    registry = require 'codex.mcp_registry'
  end)

  after_each(function()
    if manifest_path then
      registry.remove(manifest_path)
      manifest_path = nil
    end
    vim.fn = original_fn
    original_fn.delete(cache_root, 'rf')
  end)

  it('publishes and discovers the live bridge for the matching workspace', function()
    local socket_path = '/tmp/codex-nvim-registry-test.sock'
    local cwd = '/tmp/codex-nvim-registry-workspace'
    local err
    manifest_path, err = registry.publish(socket_path, cwd)

    assert(manifest_path, err)
    local record, find_err = registry.find(cwd)

    assert(record, find_err)
    eq(socket_path, record.socket_path)
    eq(cwd, record.cwd)
    eq(vim.loop.os_getpid(), record.pid)

    local directory_stat = vim.loop.fs_stat(registry.directory())
    local manifest_stat = vim.loop.fs_stat(manifest_path)
    eq(448, directory_stat.mode % 512)
    eq(384, manifest_stat.mode % 512)

    eq(true, registry.remove(manifest_path))
    manifest_path = nil
    eq(nil, vim.loop.fs_stat(registry.manifest_path(vim.loop.os_getpid())))
  end)

  it('ignores stale process manifests', function()
    local directory = registry.directory()
    original_fn.mkdir(directory, 'p', 448)
    local stale_path = registry.manifest_path(2147483647)
    original_fn.writefile({
      vim.json.encode {
        pid = 2147483647,
        socket_path = '/tmp/codex-nvim-stale.sock',
        cwd = '/tmp/codex-nvim-registry-workspace',
      },
    }, stale_path)

    local record, err = registry.find '/tmp/codex-nvim-registry-workspace'

    eq(nil, record)
    assert(err:match 'no live codex.nvim MCP bridge')
  end)

  it('keeps an explicit socket path for plugin-launched Codex sessions', function()
    local record, err = registry.resolve('/tmp/codex-nvim-explicit.sock', '/tmp/no-registered-bridge')

    assert(record, err)
    eq('/tmp/codex-nvim-explicit.sock', record.socket_path)
  end)

  describe('workspace containment', function()
    local function write_record(pid, cwd)
      original_fn.mkdir(registry.directory(), 'p', 448)
      original_fn.writefile(
        { vim.json.encode {
          pid = pid,
          socket_path = '/tmp/codex-nvim-' .. pid .. '.sock',
          cwd = cwd,
        } },
        registry.manifest_path(pid)
      )
    end
    local parent_pid = vim.loop.os_getpid()

    it('matches a Neovim workspace below the Codex cwd', function()
      write_record(1, '/tmp/ws/root/services/api/')
      write_record(parent_pid, '/tmp/other/')
      local record, err = registry.find '/tmp/ws/root'
      assert(record, err)
      eq(1, record.pid)
    end)

    it('matches a Neovim workspace above the Codex cwd', function()
      write_record(1, '/tmp/ws/root/')
      write_record(parent_pid, '/tmp/other/')
      local record, err = registry.find '/tmp/ws/root/src/deep'
      assert(record, err)
      eq(1, record.pid)
    end)

    it('prefers the closest related workspace', function()
      write_record(1, '/tmp/ws/')
      write_record(parent_pid, '/tmp/ws/root/')
      local record, err = registry.find '/tmp/ws/root/src'
      assert(record, err)
      eq(parent_pid, record.pid)
    end)

    it('rejects equally close workspaces and sibling prefixes', function()
      write_record(1, '/tmp/ws/root/a/')
      write_record(parent_pid, '/tmp/ws/root/b/')
      local record, err = registry.find '/tmp/ws/root'
      eq(nil, record)
      assert(err:match 'multiple codex.nvim MCP bridges match')

      write_record(1, '/tmp/ws/rootx/')
      write_record(parent_pid, '/tmp/elsewhere/')
      record, err = registry.find '/tmp/ws/root'
      eq(nil, record)
      assert(err:match 'multiple codex.nvim MCP bridges are live')
    end)
  end)
end)
