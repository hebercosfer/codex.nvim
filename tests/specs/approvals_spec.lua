-- luacheck: globals describe it assert eq before_each after_each

local eq = assert.equals
local approvals = require 'codex.approvals'

describe('codex.approvals', function()
  local orig_select, orig_input, orig_open

  before_each(function()
    orig_select, orig_input, orig_open = vim.ui.select, vim.ui.input, vim.ui.open
  end)

  after_each(function()
    vim.ui.select, vim.ui.input, vim.ui.open = orig_select, orig_input, orig_open
  end)

  -- Answers every vim.ui.select with the choice labelled `label`, or dismisses it when nil.
  -- Returns the list of prompts it was shown.
  local function answer_select(label)
    local shown = {}
    vim.ui.select = function(items, opts, cb)
      table.insert(shown, { items = items, prompt = opts.prompt })
      local picked
      for _, item in ipairs(items) do
        if item.label == label then
          picked = item
        end
      end
      cb(picked)
    end
    return shown
  end

  -- For prompts that pass plain strings rather than {label, value} tables.
  local function answer_raw_select(value)
    vim.ui.select = function(_, _, cb)
      cb(value)
    end
  end

  -- Answers vim.ui.input from a queue; a nil entry dismisses the prompt.
  local function answer_input(queue)
    local index = 0
    vim.ui.input = function(_, cb)
      index = index + 1
      cb(queue[index])
    end
  end

  describe('command', function()
    it('offers the default decisions and reports the chosen one', function()
      local shown = answer_select 'Accept for session'
      local response
      approvals.command({ command = 'ls -la' }, function(r)
        response = r
      end)
      eq('Allow command: ls -la', shown[1].prompt)
      local labels = {}
      for _, item in ipairs(shown[1].items) do
        table.insert(labels, item.label)
      end
      eq('Accept,Accept for session,Decline,Cancel', table.concat(labels, ','))
      eq('acceptForSession', response.decision)
    end)

    it('cancels when the prompt is dismissed', function()
      answer_select(nil)
      local response
      approvals.command({ command = 'rm -rf x' }, function(r)
        response = r
      end)
      eq('cancel', response.decision)
    end)

    it('describes a network request and labels structured decisions', function()
      local shown = answer_select 'Accept similar commands'
      local response
      approvals.command({
        networkApprovalContext = { protocol = 'https', host = 'example.com' },
        availableDecisions = { { acceptWithExecpolicyAmendment = {} }, { applyNetworkPolicyAmendment = {} } },
      }, function(r)
        response = r
      end)
      eq('Allow https network access to example.com?', shown[1].prompt)
      eq('Accept similar commands', shown[1].items[1].label)
      eq('Apply network policy', shown[1].items[2].label)
      assert(response.decision.acceptWithExecpolicyAmendment ~= nil, 'structured decision should be sent back')
    end)
  end)

  describe('file_change', function()
    it('shows the grant root and reason, and sends the chosen decision', function()
      local shown = answer_select 'Decline'
      local response
      approvals.file_change({ grantRoot = '/repo', reason = 'writes config' }, function(r)
        response = r
      end)
      eq('Allow file changes under /repo?\nwrites config', shown[1].prompt)
      eq('decline', response.decision)
    end)
  end)

  describe('user_input', function()
    it('collects an option answer and a free-text answer by question id', function()
      answer_select 'yes'
      answer_input { 'typed text' }
      local response
      approvals.user_input({
        questions = {
          { id = 'q1', question = 'Proceed?', options = { { label = 'yes' }, { label = 'no' } } },
          { id = 'q2', question = 'Name?' },
        },
      }, function(r)
        response = r
      end)
      eq('yes', response.answers.q1.answers[1])
      eq('typed text', response.answers.q2.answers[1])
    end)

    it('stops and returns what it has when a question is dismissed', function()
      answer_input { nil }
      local response
      approvals.user_input({ questions = { { id = 'q1', question = 'Name?' } } }, function(r)
        response = r
      end)
      eq(0, #vim.tbl_keys(response.answers))
    end)
  end)

  describe('mcp_elicitation', function()
    it('opens a URL and accepts when asked to open it', function()
      local opened
      vim.ui.open = function(url)
        opened = url
      end
      answer_raw_select 'Open URL'
      local response
      approvals.mcp_elicitation({ mode = 'url', url = 'https://example.com/auth', message = 'Sign in' }, function(r)
        response = r
      end)
      eq('https://example.com/auth', opened)
      eq('accept', response.action)
    end)

    it('declines a URL when asked to decline it', function()
      answer_raw_select 'Decline'
      local response
      approvals.mcp_elicitation({ mode = 'url', url = 'https://example.com' }, function(r)
        response = r
      end)
      eq('decline', response.action)
    end)

    it('collects form values in key order and coerces them to their schema types', function()
      answer_input { '3', 'yes', 'bob' }
      local response
      approvals.mcp_elicitation({
        mode = 'form',
        requestedSchema = {
          properties = {
            name = { title = 'Name' },
            count = { type = 'integer' },
            enabled = { type = 'boolean', default = false },
          },
        },
      }, function(r)
        response = r
      end)
      eq('accept', response.action)
      eq(3, response.content.count)
      eq(true, response.content.enabled)
      eq('bob', response.content.name)
    end)

    it('cancels when a form prompt is dismissed', function()
      answer_input { nil }
      local response
      approvals.mcp_elicitation({ mode = 'form', requestedSchema = { properties = { name = {} } } }, function(r)
        response = r
      end)
      eq('cancel', response.action)
    end)
  end)
end)
