-- luacheck: globals describe it assert eq before_each after_each

local eq = assert.equals
local prompt = require 'codex.prompt'
local state = require 'codex.state'

describe('codex.prompt', function()
  local cwd

  before_each(function()
    cwd = vim.fn.getcwd()
    state.app = state.app or {}
    state.app.pending_context = {}
  end)

  describe('selection_reference', function()
    local function selection(from_line, to_line)
      return {
        filePath = cwd .. '/lua/example.lua',
        selection = {
          isEmpty = false,
          start = { line = from_line },
          ['end'] = { line = to_line },
        },
      }
    end

    it('references a single line as #L<n>', function()
      eq('@lua/example.lua#L3', prompt.selection_reference(selection(2, 2)))
    end)

    it('references a range as #L<from>-L<to>', function()
      eq('@lua/example.lua#L3-L5', prompt.selection_reference(selection(2, 4)))
    end)

    it('returns nothing for an empty or missing selection', function()
      eq(nil, prompt.selection_reference(nil))
      eq(nil, prompt.selection_reference { filePath = 'x', selection = { isEmpty = true } })
    end)
  end)

  describe('references', function()
    it('finds @path#L ranges and bare paths that contain a slash', function()
      local refs = prompt.references 'see @lua/a.lua#L10-L12 and lua/b.lua#L4.'
      eq(2, #refs)
      eq('lua/a.lua', refs[1].path)
      eq(10, refs[1].start_line)
      eq(12, refs[1].end_line)
      eq('lua/b.lua', refs[2].path)
      eq(4, refs[2].start_line)
      eq(4, refs[2].end_line)
    end)

    it('ignores a bare word without a slash unless it is marked with @', function()
      eq(0, #prompt.references 'use foo#L3 here')
      eq(1, #prompt.references 'use @foo#L3 here')
    end)

    it('collects each distinct range once', function()
      eq(1, #prompt.references '@lua/a.lua#L1 @lua/a.lua#L1')
    end)
  end)

  describe('input_reference', function()
    it('returns the text untouched when raw is set', function()
      eq('hello', prompt.input_reference('hello', { raw = true }, {}))
    end)

    it('puts a selection reference in front of the prompt text', function()
      local sel = {
        filePath = cwd .. '/lua/example.lua',
        selection = { isEmpty = false, start = { line = 0 }, ['end'] = { line = 0 } },
      }
      eq('@lua/example.lua#L1 explain it', prompt.input_reference('explain it', { selection = sel }, {}))
    end)

    it('uses the active buffer when there is no text and no selection', function()
      local out = prompt.input_reference('', { active_context = { path = cwd .. '/lua/example.lua' } }, { include_active_buffer_context = true })
      eq('@lua/example.lua ', out)
    end)

    it('sends nothing for an empty prompt when active context is off', function()
      eq('', prompt.input_reference('', {}, { include_active_buffer_context = false }))
    end)
  end)

  describe('terminal', function()
    it('appends the active buffer description when there is no selection', function()
      local out = prompt.terminal('fix it', { active_description = 'Active file: lua/x.lua' }, { include_active_buffer_context = true })
      eq('fix it\n\nActive file: lua/x.lua', out)
    end)

    it('adds a selection reference after the prompt text', function()
      local sel = {
        filePath = cwd .. '/lua/example.lua',
        selection = { isEmpty = false, start = { line = 1 }, ['end'] = { line = 2 } },
      }
      eq('refactor\n\nSelected context: @lua/example.lua#L2-L3', prompt.terminal('refactor', { selection = sel }, {}))
    end)

    it('turns pending app and skill items into prefixes and file items into a context list', function()
      local out = prompt.terminal('do it', {
        pending_context = {
          { path = 'app://github' },
          { type = 'skill', name = 'review' },
          { path = cwd .. '/lua/x.lua', line_start = 0, line_end = 4, name = 'x.lua' },
        },
      }, {})
      eq('$github $review do it\n\nAdditional Neovim context:\n- x.lua:1-5', out)
    end)

    it('empties the pending context it was given', function()
      local pending = { { path = cwd .. '/lua/x.lua', name = 'x.lua' } }
      prompt.terminal('go', { pending_context = pending }, {})
      eq(0, #pending)
    end)
  end)

  describe('injection_items_from_text', function()
    it('builds one message per referenced range, read from the file on disk', function()
      local file = vim.fn.tempname() .. '.txt'
      vim.fn.writefile({ 'line one', 'line two', 'line three' }, file)

      local items = prompt.injection_items_from_text('check @' .. file .. '#L2-L3 please')
      eq(1, #items)
      eq('user', items[1].role)
      local text = items[1].content[1].text
      assert(text:find('line two\nline three', 1, true), 'the referenced lines should be injected: ' .. text)
      assert(not text:find('line one', 1, true), 'lines outside the range should not be injected')
      vim.fn.delete(file)
    end)

    it('skips references to files that do not exist', function()
      eq(0, #prompt.injection_items_from_text '@/no/such/file/anywhere.lua#L1')
    end)
  end)
end)
