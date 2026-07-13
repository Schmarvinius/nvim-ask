local M = {}

M.config = {
  keybind = "<leader>ai",
  -- Which backend to use. See lua/nvim-ask/backends/ for the interface.
  backend = "claude",
  window = {
    width = 0.8,
    height = 0.8,
    border = "rounded",
    min_width = 40,
    min_height = 15,
  },
  -- Backend-specific options. Each backend reads its own table (config_key).
  claude = {
    model = nil,
    timeout = 120,
  },
  -- Extra editor context to include in the prompt. See nvim-ask.context.
  context = {
    surrounding_lines = 0,
    whole_file = false,
    diagnostics = false,
    git_diff = false,
  },
  -- When true, applying a suggestion first shows a diff you must confirm.
  confirm_apply = true,
  -- Additional / overriding preset prompt templates (merged over defaults).
  presets = {},
}

local current_state = nil

--- Validate and normalize the merged config. Emits warnings and repairs
--- invalid values rather than throwing, so a bad option never breaks setup.
--- @param config table
--- @return table config
local function validate_config(config)
  local backends = require("nvim-ask.backends")

  if type(config.backend) ~= "string" then
    vim.notify(
      "nvim-ask: config.backend must be a string; falling back to 'claude'",
      vim.log.levels.WARN
    )
    config.backend = "claude"
  end

  if not backends.get(config.backend) then
    vim.notify(
      string.format(
        "nvim-ask: unknown backend '%s' (available: %s); falling back to 'claude'",
        tostring(config.backend),
        table.concat(backends.names(), ", ")
      ),
      vim.log.levels.WARN
    )
    config.backend = "claude"
  end

  -- Window fractions must be in (0, 1].
  for _, key in ipairs({ "width", "height" }) do
    local v = config.window[key]
    if type(v) ~= "number" or v <= 0 or v > 1 then
      vim.notify(
        string.format("nvim-ask: window.%s must be a number in (0, 1]; using default", key),
        vim.log.levels.WARN
      )
      config.window[key] = 0.8
    end
  end

  local timeout = config.claude and config.claude.timeout
  if timeout ~= nil and (type(timeout) ~= "number" or timeout < 0) then
    vim.notify(
      "nvim-ask: claude.timeout must be a non-negative number; using default 120",
      vim.log.levels.WARN
    )
    config.claude.timeout = 120
  end

  local sl = config.context and config.context.surrounding_lines
  if sl ~= nil and (type(sl) ~= "number" or sl < 0) then
    vim.notify(
      "nvim-ask: context.surrounding_lines must be a non-negative number; using 0",
      vim.log.levels.WARN
    )
    config.context.surrounding_lines = 0
  end

  return config
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  M.config = validate_config(M.config)

  vim.keymap.set("v", M.config.keybind, function()
    -- Capture the current visual selection BEFORE leaving visual mode.
    -- The '< and '> marks are only updated after visual mode exits, so
    -- reading them here would return the *previous* selection. Instead we
    -- read the live selection endpoints directly.
    local start_pos = vim.fn.getpos("v") -- visual start
    local end_pos = vim.fn.getpos(".") -- cursor (visual end)

    -- Normalize so start comes before end.
    if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
      start_pos, end_pos = end_pos, start_pos
    end

    -- Leave visual mode.
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
      "nx",
      false
    )

    M.open({ range = true, start_pos = start_pos, end_pos = end_pos })
  end, { desc = "nvim-ask: open AI assistant" })

  vim.keymap.set("n", M.config.keybind, function()
    M.open({ range = false })
  end, { desc = "nvim-ask: open AI assistant (no selection)" })
end

function M.open(opts)
  opts = opts or {}

  -- Single instance: focus existing overlay if open
  if current_state and current_state.container_win and vim.api.nvim_win_is_valid(current_state.container_win) then
    vim.api.nvim_set_current_win(current_state.prompt_win)
    return
  end

  -- Resolve an initial prompt from an explicit prompt or a named preset.
  local initial_prompt = opts.prompt
  if not initial_prompt and opts.preset then
    local presets = require("nvim-ask.presets")
    initial_prompt = presets.get(M.config, opts.preset)
    if not initial_prompt then
      vim.notify(
        "nvim-ask: unknown preset '" .. tostring(opts.preset) .. "'",
        vim.log.levels.WARN
      )
    end
  end

  local context = M._capture_context(opts)
  local ui = require("nvim-ask.ui")
  current_state = ui.open(context, M.config, { initial_prompt = initial_prompt })
end

--- Open the overlay via a named preset, choosing interactively when no name
--- (or an unknown name) is given.
--- @param name string|nil
--- @param opts table|nil forwarded to M.open (e.g. { range = true })
function M.open_preset(name, opts)
  opts = opts or {}
  local presets = require("nvim-ask.presets")

  if name and name ~= "" then
    opts.preset = name
    M.open(opts)
    return
  end

  vim.ui.select(presets.names(M.config), { prompt = "nvim-ask preset:" }, function(choice)
    if not choice then
      return
    end
    opts.preset = choice
    M.open(opts)
  end)
end

--- Sorted list of preset names (for command completion).
function M.preset_names()
  return require("nvim-ask.presets").names(M.config)
end

function M.get_state()
  return current_state
end

function M.clear_state()
  current_state = nil
end

function M._capture_context(opts)
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local filetype = vim.bo[buf].filetype
  local selection = nil

  if opts.range then
    -- Prefer explicit positions captured live from visual mode (see the
    -- visual keymap in setup). Fall back to the '< / '> marks for the
    -- :NvimAsk command path, which sets them correctly via command-line mode.
    local start_pos = opts.start_pos or vim.fn.getpos("'<")
    local end_pos = opts.end_pos or vim.fn.getpos("'>")
    local start_line = start_pos[2]
    local end_line = end_pos[2]

    if start_line > 0 and end_line > 0 then
      local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
      local mode = vim.fn.visualmode()
      selection = {
        start_line = start_line,
        end_line = end_line,
        lines = lines,
        mode = mode,
      }
    end
  end

  local context = {
    buf = buf,
    win = win,
    filetype = filetype,
    selection = selection,
  }

  -- Gather optional extra context now, while the original buffer is current.
  local ok, ctx = pcall(function()
    return require("nvim-ask.context").gather(context, M.config.context)
  end)
  context.extra = (ok and ctx) or {}

  return context
end

return M
