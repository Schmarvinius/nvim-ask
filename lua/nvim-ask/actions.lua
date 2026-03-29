local M = {}

local parser = require("nvim-ask.parser")

--- Apply the response code to the original buffer (replace selection or paste at cursor)
function M.apply(state)
  if not state or not state.accumulated_text or state.accumulated_text == "" then
    vim.notify("nvim-ask: no response to apply", vim.log.levels.WARN)
    return
  end

  local context = state.context
  if not vim.api.nvim_buf_is_valid(context.buf) then
    vim.notify("nvim-ask: original buffer no longer exists", vim.log.levels.ERROR)
    return
  end

  -- Extract code from response (prefer code block, fall back to full response)
  local code = parser.get_primary_code(state.accumulated_text)
  if not code then
    code = vim.trim(state.accumulated_text)
  end

  local new_lines = vim.split(code, "\n", { plain = true })

  if context.selection then
    -- Replace the original selection
    local start_line = context.selection.start_line - 1 -- 0-indexed
    local end_line = context.selection.end_line
    vim.api.nvim_buf_set_lines(context.buf, start_line, end_line, false, new_lines)
    vim.notify("nvim-ask: applied " .. #new_lines .. " lines", vim.log.levels.INFO)
  else
    -- No selection: paste at current cursor position in the original window
    if vim.api.nvim_win_is_valid(context.win) then
      local cursor = vim.api.nvim_win_get_cursor(context.win)
      local line = cursor[1] -- 1-indexed
      vim.api.nvim_buf_set_lines(context.buf, line, line, false, new_lines)
      vim.notify("nvim-ask: inserted " .. #new_lines .. " lines", vim.log.levels.INFO)
    else
      vim.notify("nvim-ask: original window no longer exists", vim.log.levels.ERROR)
      return
    end
  end

  M.close(state)
end

--- Yank response (or primary code block) to system clipboard
function M.yank(state)
  if not state or not state.accumulated_text or state.accumulated_text == "" then
    vim.notify("nvim-ask: no response to yank", vim.log.levels.WARN)
    return
  end

  local code = parser.get_primary_code(state.accumulated_text)
  local text = code or state.accumulated_text

  vim.fn.setreg("+", text)
  vim.notify("nvim-ask: yanked to clipboard", vim.log.levels.INFO)
end

--- Retry: clear response and re-send the same prompt
function M.retry(state)
  if not state or state.sending then
    return
  end

  -- Stop any existing job
  if state.job_id then
    pcall(vim.fn.jobstop, state.job_id)
    state.job_id = nil
  end

  -- Clear response
  state.accumulated_text = ""
  if state.response_buf and vim.api.nvim_buf_is_valid(state.response_buf) then
    vim.bo[state.response_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.response_buf, 0, -1, false, { "" })
    vim.bo[state.response_buf].modifiable = false
  end

  -- Re-enable prompt editing
  if state.prompt_buf and vim.api.nvim_buf_is_valid(state.prompt_buf) then
    vim.bo[state.prompt_buf].modifiable = true
  end

  -- Re-send
  local ui = require("nvim-ask.ui")
  ui._send_prompt(state)
end

--- Close the overlay
function M.close(state)
  local ui = require("nvim-ask.ui")
  ui.close(state)
end

return M
