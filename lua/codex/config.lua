local M = {}

M.defaults = {
  backend = 'app_server', -- app_server | terminal
  keymaps = {
    toggle = '<leader>cc',
    open = '<leader>cC',
    session_new = '<leader>cn',
    yolo = '<leader>cy',
    quit = '<C-q>',
    send = '<leader>cs',
    diff_accept = '<leader>ca',
    diff_reject = '<leader>cd',
    interrupt = '<C-c>',
  },
  border = 'rounded',
  title = ' Codex ', -- shown on the float's border; false or '' for none
  title_pos = 'center', -- left | center | right
  width = 0.8, -- fraction of the editor (float) or of its columns (panel)
  height = 0.8,
  min_width = 80, -- cells; the float never gets narrower than this (capped at the editor width)
  min_height = 24, -- lines; the float never gets shorter than this (capped at the editor height)
  panel_width = 0.25, -- fraction of the columns when panel = true
  cmd = 'codex',
  model = nil,
  autoinstall = true,
  panel = false,
  use_buffer = false,
  track_selection = true,
  include_active_buffer_context = true,
  visual_demotion_delay_ms = 50,
  focus_after_send = false,
  selection_prompt = 'Use the selected Neovim context.',
  session_list = {
    width = 7,
  },
  app_server = {
    ui = 'terminal', -- terminal | buffer
    listen = 'stdio://',
    port = nil,
    port_range = { min = 45000, max = 45999 },
    experimental = true,
    auto_start = true,
    dynamic_tools = true,
    open_terminal = true,
    editor_instructions = true,
    service_name = 'codex_nvim',
    approval_policy = nil,
    sandbox = nil,
    enable_features = { 'apps' },
    mcp_status_detail = 'toolsAndAuthOnly',
  },
}

local function validate_number(name, value, min, max)
  assert(type(value) == 'number', name .. ' must be a number')
  assert(value >= min and value <= max, name .. ' must be between ' .. min .. ' and ' .. max)
end

function M.apply(user_config)
  local config = vim.deepcopy(M.defaults)

  if user_config then
    config = vim.tbl_deep_extend('force', config, user_config)
  end

  -- keymaps merges per key: a configured key overrides its default, the rest keep theirs.
  -- `keymaps = false` maps nothing at all.
  if config.keymaps == false then
    config.keymaps = {}
  end

  assert(config.backend == 'app_server' or config.backend == 'terminal', 'backend must be app_server or terminal')
  assert(type(config.keymaps) == 'table', 'keymaps must be a table or false')
  for name, lhs in pairs(config.keymaps) do
    if lhs == '' then
      config.keymaps[name] = false
    end
    assert(config.keymaps[name] == false or type(config.keymaps[name]) == 'string', 'keymaps.' .. name .. ' must be a string or false')
  end
  assert(type(config.cmd) == 'string' or type(config.cmd) == 'table', 'cmd must be a string or list')
  validate_number('width', config.width, 0.1, 1)
  validate_number('height', config.height, 0.1, 1)
  assert(type(config.min_width) == 'number' and config.min_width >= 1, 'min_width must be at least 1')
  validate_number('panel_width', config.panel_width, 0.1, 1)
  assert(config.title == false or type(config.title) == 'string', 'title must be a string or false')
  assert(config.title_pos == 'left' or config.title_pos == 'center' or config.title_pos == 'right', 'title_pos must be left, center or right')
  assert(type(config.min_height) == 'number' and config.min_height >= 1, 'min_height must be at least 1')
  assert(type(config.autoinstall) == 'boolean', 'autoinstall must be a boolean')
  assert(type(config.panel) == 'boolean', 'panel must be a boolean')
  assert(type(config.use_buffer) == 'boolean', 'use_buffer must be a boolean')
  assert(type(config.track_selection) == 'boolean', 'track_selection must be a boolean')
  assert(type(config.include_active_buffer_context) == 'boolean', 'include_active_buffer_context must be a boolean')
  assert(type(config.visual_demotion_delay_ms) == 'number' and config.visual_demotion_delay_ms >= 0, 'visual_demotion_delay_ms must be non-negative')
  assert(type(config.selection_prompt) == 'string', 'selection_prompt must be a string')
  assert(type(config.session_list) == 'table', 'session_list must be a table')
  assert(type(config.session_list.width) == 'number' and config.session_list.width >= 1, 'session_list.width must be at least 1')
  assert(type(config.app_server) == 'table', 'app_server must be a table')
  assert(config.app_server.ui == 'terminal' or config.app_server.ui == 'buffer', 'app_server.ui must be terminal or buffer')
  assert(type(config.app_server.open_terminal) == 'boolean', 'app_server.open_terminal must be a boolean')
  assert(config.app_server.port == nil or type(config.app_server.port) == 'number', 'app_server.port must be nil or a number')
  assert(type(config.app_server.port_range) == 'table', 'app_server.port_range must be a table')
  assert(type(config.app_server.port_range.min) == 'number', 'app_server.port_range.min must be a number')
  assert(type(config.app_server.port_range.max) == 'number', 'app_server.port_range.max must be a number')
  assert(config.app_server.port_range.min > 0 and config.app_server.port_range.max <= 65535, 'app_server.port_range must use valid ports')
  assert(config.app_server.port_range.min <= config.app_server.port_range.max, 'app_server.port_range min must be <= max')

  return config
end

return M
