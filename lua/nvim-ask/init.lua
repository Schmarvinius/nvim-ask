local M = {}

M.config = {
  keybind = "<leader>ai",
  window = {
    width = 0.8,
    height = 0.8,
    border = "rounded",
    min_width = 40,
    min_height = 15,
  },
  claude = {
    model = nil,
    max_tokens = nil,
    timeout = 120,
  },
}

local current_state = nil

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.keymap.set("v", M.config.keybind, function()
    M.open({ range = true })
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

  local context = M._capture_context(opts)
  local ui = require("nvim-ask.ui")
  current_state = ui.open(context, M.config)
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
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
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

  return {
    buf = buf,
    win = win,
    filetype = filetype,
    selection = selection,
  }
end

return M
