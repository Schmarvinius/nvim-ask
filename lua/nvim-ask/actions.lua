local M = {}

local parser = require("nvim-ask.parser")

--- Resolve the list of applyable code blocks from the current response.
--- Falls back to a live parse, then to the whole response as a single block.
--- @param state table
--- @return table[] blocks list of { code, lang }
local function resolve_blocks(state)
  if state.parsed_blocks and #state.parsed_blocks > 0 then
    return state.parsed_blocks
  end
  local parsed = parser.split_response(state.accumulated_text or "")
  if parsed.blocks and #parsed.blocks > 0 then
    return parsed.blocks
  end
  local code = vim.trim(state.accumulated_text or "")
  if code ~= "" then
    return { { code = code, lang = nil } }
  end
  return {}
end

--- Write the given lines into the original buffer (replace selection or insert
--- at the cursor), then close the overlay.
--- @param state table
--- @param new_lines string[]
function M._write(state, new_lines)
  local context = state.context
  if not vim.api.nvim_buf_is_valid(context.buf) then
    vim.notify("nvim-ask: original buffer no longer exists", vim.log.levels.ERROR)
    return
  end

  if context.selection then
    local start_line = context.selection.start_line - 1 -- 0-indexed
    local end_line = context.selection.end_line
    vim.api.nvim_buf_set_lines(context.buf, start_line, end_line, false, new_lines)
    vim.notify("nvim-ask: applied " .. #new_lines .. " lines", vim.log.levels.INFO)
  else
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

--- Apply a single parsed code block, honoring the confirm_apply setting.
--- @param state table
--- @param block table { code, lang }
function M._apply_block(state, block)
  local new_lines = vim.split(block.code, "\n", { plain = true })

  -- Direct write when confirmation is disabled.
  if state.config and state.config.confirm_apply == false then
    M._write(state, new_lines)
    return
  end

  local old_lines = {}
  if state.context.selection then
    old_lines = state.context.selection.lines
  end

  local ft = state.context.filetype
  if not ft or ft == "" then
    ft = block.lang
  end

  local title = state.context.selection and " Preview changes " or " Preview insertion "

  require("nvim-ask.diff").preview({
    old_lines = old_lines,
    new_lines = new_lines,
    filetype = ft,
    title = title,
    border = state.config and state.config.window and state.config.window.border,
    on_accept = function()
      M._write(state, new_lines)
    end,
    on_reject = function()
      require("nvim-ask.ui")._focus_response_side(state)
    end,
  })
end

--- Apply the response code to the original buffer. When the response contains
--- multiple code blocks, the user is asked which to apply. When confirm_apply
--- is enabled (default), a diff preview must be accepted first.
function M.apply(state)
  if not state or not state.accumulated_text or state.accumulated_text == "" then
    vim.notify("nvim-ask: no response to apply", vim.log.levels.WARN)
    return
  end
  if not vim.api.nvim_buf_is_valid(state.context.buf) then
    vim.notify("nvim-ask: original buffer no longer exists", vim.log.levels.ERROR)
    return
  end

  local blocks = resolve_blocks(state)
  if #blocks == 0 then
    vim.notify("nvim-ask: no code to apply", vim.log.levels.WARN)
    return
  end

  if #blocks == 1 then
    M._apply_block(state, blocks[1])
    return
  end

  -- Multiple code blocks: let the user choose which one to apply.
  local items = {}
  for i, b in ipairs(blocks) do
    local n = #vim.split(b.code, "\n", { plain = true })
    items[i] = string.format("Block %d — %s (%d line%s)", i, b.lang or "text", n, n == 1 and "" or "s")
  end
  vim.ui.select(items, { prompt = "Apply which code block?" }, function(choice, idx)
    if not choice or not idx then
      return
    end
    M._apply_block(state, blocks[idx])
  end)
end

--- Yank response (or primary code block) to system clipboard
function M.yank(state)
  if not state or not state.accumulated_text or state.accumulated_text == "" then
    vim.notify("nvim-ask: no response to yank", vim.log.levels.WARN)
    return
  end

  local code = state.parsed_code
  if not code or code == "" then
    code = parser.get_primary_code(state.accumulated_text)
  end
  local text = code or state.accumulated_text

  vim.fn.setreg("+", text)
  vim.notify("nvim-ask: yanked to clipboard", vim.log.levels.INFO)
end

--- Retry: re-send the last prompt. In a multi-turn session this discards the
--- most recent (user, assistant) turn so the retried answer replaces it rather
--- than stacking a duplicate turn into the transcript.
function M.retry(state)
  if not state or state.sending then
    return
  end

  -- Stop any existing request
  if state.handle and state.backend then
    pcall(state.backend.stop, state.handle)
    state.handle = nil
  end

  -- Drop the last recorded turn (assistant + user) if present.
  if state.messages and #state.messages >= 2 then
    table.remove(state.messages) -- assistant
    table.remove(state.messages) -- user
  end

  -- Restore the previous prompt text (the follow-up hook may have cleared it).
  if state.prompt_buf and vim.api.nvim_buf_is_valid(state.prompt_buf) then
    vim.bo[state.prompt_buf].modifiable = true
    local lines = vim.split(state.user_prompt or "", "\n", { plain = true })
    vim.api.nvim_buf_set_lines(state.prompt_buf, 0, -1, false, lines)
  end

  -- Clear response
  state.accumulated_text = ""
  if state.response_buf and vim.api.nvim_buf_is_valid(state.response_buf) then
    vim.bo[state.response_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.response_buf, 0, -1, false, { "" })
    vim.bo[state.response_buf].modifiable = false
  end

  -- Re-send
  require("nvim-ask.ui")._send_prompt(state)
end

--- Close the overlay
function M.close(state)
  require("nvim-ask.ui").close(state)
end

return M
