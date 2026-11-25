local eq = assert.equals
local util = require 'codex.util'

describe('codex util', function()
  it('extracts a bare string executable', function()
    eq('codex', util.executable_from_cmd 'codex')
    eq(nil, util.executable_from_cmd 'codex --version')
  end)

  it('preserves a command string with arguments', function()
    local command = 'codex --help'
    eq(command, util.resolve_cmd(command))
  end)

  it('returns text unchanged for string content', function()
    eq('hello', util.text_content 'hello')
  end)

  it('JSON encodes structured content', function()
    eq('{"text":"hello"}', util.text_content { text = 'hello' })
  end)

  it('falls back to tostring when content cannot be JSON encoded', function()
    local value = function() end
    eq(tostring(value), util.text_content(value))
  end)
end)
