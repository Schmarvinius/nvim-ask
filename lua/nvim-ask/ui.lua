local M = {}

local actions -- lazy-loaded to avoid circular require

local function get_actions()
  if not actions then
    actions = require("nvim-ask.actions")
  end
  return actions
end

--- Compute container dimensions from config percentages
local function compute_layout(config)
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines - vim.o.cmdheight - 1 -- subtract statusline

  local w = math.floor(editor_w * config.window.width)
  local h = math.floor(editor_h * config.window.height)
  local row = math.floor((editor_h - h) / 2)
  local col = math.floor((editor_w - w) / 2)

  return {
    width = w,
    height = h,
    row = row,
    col = col,
    inner_width = w - 2, -- subtract left+right border
    inner_height = h - 2, -- subtract top+bottom border
    inner_row = row + 1,
    inner_col = col + 1,
  }
end

--- Create a scratch buffer with given options
local function create_buf(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  if opts.filetype then
    vim.bo[buf].filetype = opts.filetype
  end
  if opts.lines then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)
  end
  if opts.modifiable == false then
    vim.bo[buf].modifiable = false
  end
  return buf
end

--- Create a floating window
local function create_win(buf, win_opts, enter)
  local config = {
    relative = "editor",
    row = win_opts.row,
    col = win_opts.col,
    width = win_opts.width,
    height = win_opts.height,
    style = "minimal",
    border = win_opts.border or "none",
    focusable = win_opts.focusable ~= false,
    zindex = win_opts.zindex or 50,
  }
  if win_opts.title then
    config.title = win_opts.title
    config.title_pos = "center"
  end
  if win_opts.footer then
    config.footer = win_opts.footer
    config.footer_pos = "center"
  end
  local win = vim.api.nvim_open_win(buf, enter or false, config)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = true
  vim.wo[win].cursorline = false
  return win
end

--- Set common keymaps for a buffer within the overlay
local function set_close_keymap(buf, state)
  vim.keymap.set("n", "q", function()
    get_actions().close(state)
  end, { buffer = buf, nowait = true })
end

--- Open the full overlay UI
--- @param context table { buf, win, filetype, selection }
--- @param config table plugin config
--- @return table state
function M.open(context, config)
  local layout = compute_layout(config)

  -- Guard: terminal too small
  if layout.width < config.window.min_width or layout.height < config.window.min_height then
    vim.notify("nvim-ask: terminal too small (need at least " .. config.window.min_width .. "x" .. config.window.min_height .. ")", vim.log.levels.ERROR)
    return nil
  end

  local state = {
    context = context,
    config = config,
    layout = layout,
    ns_id = vim.api.nvim_create_namespace("nvim_ask"),
    sending = false,
    accumulated_text = "",
    job_id = nil,
    user_prompt = "",
  }

  -- Container (border-only window)
  local container_buf = create_buf({ lines = {} })
  state.container_buf = container_buf
  state.container_win = create_win(container_buf, {
    row = layout.row,
    col = layout.col,
    width = layout.width,
    height = layout.height,
    border = config.window.border,
    title = " nvim-ask ",
    focusable = false,
    zindex = 49,
  }, false)

  -- Code section
  local code_lines
  local code_height
  if context.selection and #context.selection.lines > 0 then
    code_lines = context.selection.lines
    code_height = math.min(#code_lines, math.floor(layout.inner_height * 0.35))
  else
    code_lines = { "  No code selected — general question mode" }
    code_height = 1
  end

  local code_buf = create_buf({
    lines = code_lines,
    filetype = context.selection and context.filetype or nil,
    modifiable = false,
  })
  state.code_buf = code_buf

  local code_row = layout.inner_row
  state.code_win = create_win(code_buf, {
    row = code_row,
    col = layout.inner_col,
    width = layout.inner_width,
    height = code_height,
    border = "none",
    title = nil,
    zindex = 51,
  }, false)
  vim.wo[state.code_win].cursorline = false

  -- If no selection, use Comment highlight for the placeholder text
  if not context.selection then
    vim.api.nvim_buf_set_extmark(code_buf, state.ns_id, 0, 0, {
      end_col = #code_lines[1],
      hl_group = "Comment",
    })
  end

  -- Prompt section
  local prompt_height = 3
  local prompt_row = code_row + code_height + 1
  local prompt_buf = create_buf({ lines = { "" } })
  state.prompt_buf = prompt_buf
  state.prompt_win = create_win(prompt_buf, {
    row = prompt_row,
    col = layout.inner_col,
    width = layout.inner_width,
    height = prompt_height,
    border = { "─", "─", "─", "│", "─", "─", "─", "│" },
    title = " Prompt ",
    footer = " <CR> Send  |  q Close ",
    zindex = 51,
  }, true)

  -- Focus prompt in insert mode
  vim.cmd("startinsert")

  -- Prompt keymaps
  set_close_keymap(prompt_buf, state)

  vim.keymap.set("i", "<CR>", function()
    M._send_prompt(state)
  end, { buffer = prompt_buf })

  vim.keymap.set("n", "<CR>", function()
    M._send_prompt(state)
  end, { buffer = prompt_buf })

  vim.keymap.set("n", "<Tab>", function()
    if state.response_win and vim.api.nvim_win_is_valid(state.response_win) then
      vim.api.nvim_set_current_win(state.response_win)
    end
  end, { buffer = prompt_buf })

  -- Store remaining layout info for response section
  state.response_start_row = prompt_row + prompt_height + 2 -- +2 for prompt border
  state.response_available_height = layout.inner_row + layout.inner_height - state.response_start_row

  -- Autocommands for cleanup
  state.augroup = vim.api.nvim_create_augroup("nvim_ask_" .. container_buf, { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = state.augroup,
    pattern = tostring(state.container_win),
    callback = function()
      get_actions().close(state)
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = state.augroup,
    callback = function()
      vim.defer_fn(function()
        M._relayout(state)
      end, 20)
    end,
  })

  return state
end

--- Create and show the response section
function M.show_response_section(state)
  if state.response_win and vim.api.nvim_win_is_valid(state.response_win) then
    return -- already visible
  end

  local response_height = math.max(state.response_available_height, 3)
  local response_buf = create_buf({ lines = { "" }, filetype = "markdown" })
  state.response_buf = response_buf

  state.response_win = create_win(response_buf, {
    row = state.response_start_row,
    col = state.layout.inner_col,
    width = state.layout.inner_width,
    height = response_height,
    border = { "─", "─", "─", "│", "─", "─", "─", "│" },
    title = " Response ",
    footer = " <CR> Apply  |  y Yank  |  r Retry  |  q Close ",
    zindex = 51,
  }, false)

  -- Enable treesitter for markdown
  pcall(vim.treesitter.start, response_buf, "markdown")

  -- Response keymaps
  set_close_keymap(response_buf, state)

  vim.keymap.set("n", "<CR>", function()
    get_actions().apply(state)
  end, { buffer = response_buf })

  vim.keymap.set("n", "y", function()
    get_actions().yank(state)
  end, { buffer = response_buf })

  vim.keymap.set("n", "r", function()
    get_actions().retry(state)
  end, { buffer = response_buf })

  vim.keymap.set("n", "<Tab>", function()
    if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
      vim.api.nvim_set_current_win(state.prompt_win)
    end
  end, { buffer = response_buf })

  vim.keymap.set("n", "<S-Tab>", function()
    if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
      vim.api.nvim_set_current_win(state.prompt_win)
    end
  end, { buffer = response_buf })
end

--- Update the response buffer with accumulated text
function M.update_response(state, text)
  state.accumulated_text = state.accumulated_text .. text

  if not state.response_buf or not vim.api.nvim_buf_is_valid(state.response_buf) then
    return
  end

  local lines = vim.split(state.accumulated_text, "\n", { plain = true })
  vim.bo[state.response_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.response_buf, 0, -1, false, lines)
  vim.bo[state.response_buf].modifiable = false

  -- Scroll to bottom
  if state.response_win and vim.api.nvim_win_is_valid(state.response_win) then
    local line_count = vim.api.nvim_buf_line_count(state.response_buf)
    pcall(vim.api.nvim_win_set_cursor, state.response_win, { line_count, 0 })
  end
end

--- Set a status message in the response area
function M.set_status(state, status)
  if not state.response_buf or not vim.api.nvim_buf_is_valid(state.response_buf) then
    return
  end
  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(state.response_buf, state.ns_id, 0, -1)
  if status then
    vim.api.nvim_buf_set_extmark(state.response_buf, state.ns_id, 0, 0, {
      virt_text = { { status, "Comment" } },
      virt_text_pos = "overlay",
    })
  end
end

--- Internal: send the prompt to Claude
function M._send_prompt(state)
  if state.sending then
    return
  end

  -- Get prompt text
  local prompt_lines = vim.api.nvim_buf_get_lines(state.prompt_buf, 0, -1, false)
  local user_prompt = table.concat(prompt_lines, "\n")
  if vim.trim(user_prompt) == "" then
    vim.notify("nvim-ask: please enter a prompt", vim.log.levels.WARN)
    return
  end

  state.sending = true
  state.user_prompt = user_prompt
  state.accumulated_text = ""

  -- Leave insert mode if in it
  vim.cmd("stopinsert")

  -- Make prompt read-only during request
  vim.bo[state.prompt_buf].modifiable = false

  -- Show response section
  M.show_response_section(state)

  -- Start spinner
  M._start_spinner(state)

  -- Send to Claude
  local claude = require("nvim-ask.claude")
  local full_prompt = claude.build_prompt(state.context, user_prompt)

  state.job_id = claude.send(full_prompt, state.config, {
    on_delta = function(text)
      M._stop_spinner(state)
      vim.schedule(function()
        M.update_response(state, text)
      end)
    end,
    on_complete = function(full_text)
      vim.schedule(function()
        M._stop_spinner(state)
        state.sending = false
        -- Final update with complete text to ensure nothing is missed
        if state.accumulated_text ~= full_text and full_text ~= "" then
          state.accumulated_text = full_text
          if state.response_buf and vim.api.nvim_buf_is_valid(state.response_buf) then
            local lines = vim.split(full_text, "\n", { plain = true })
            vim.bo[state.response_buf].modifiable = true
            vim.api.nvim_buf_set_lines(state.response_buf, 0, -1, false, lines)
            vim.bo[state.response_buf].modifiable = false
          end
        end
        M.set_status(state, nil)
        -- Focus response window
        if state.response_win and vim.api.nvim_win_is_valid(state.response_win) then
          vim.api.nvim_set_current_win(state.response_win)
        end
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        M._stop_spinner(state)
        state.sending = false
        vim.bo[state.prompt_buf].modifiable = true
        if state.response_buf and vim.api.nvim_buf_is_valid(state.response_buf) then
          vim.bo[state.response_buf].modifiable = true
          vim.api.nvim_buf_set_lines(state.response_buf, 0, -1, false, { "Error: " .. (err or "unknown error") })
          vim.bo[state.response_buf].modifiable = false
        end
      end)
    end,
  })
end

--- Spinner frames
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

function M._start_spinner(state)
  if state.spinner_timer then
    return
  end
  local frame_idx = 0
  state.spinner_timer = vim.uv.new_timer()
  state.spinner_timer:start(0, 80, vim.schedule_wrap(function()
    frame_idx = (frame_idx % #spinner_frames) + 1
    if state.response_buf and vim.api.nvim_buf_is_valid(state.response_buf) then
      vim.api.nvim_buf_clear_namespace(state.response_buf, state.ns_id, 0, -1)
      vim.api.nvim_buf_set_extmark(state.response_buf, state.ns_id, 0, 0, {
        virt_text = { { spinner_frames[frame_idx] .. " Thinking...", "Comment" } },
        virt_text_pos = "overlay",
      })
    end
  end))
end

function M._stop_spinner(state)
  if state.spinner_timer then
    state.spinner_timer:stop()
    state.spinner_timer:close()
    state.spinner_timer = nil
  end
  if state.response_buf and vim.api.nvim_buf_is_valid(state.response_buf) then
    pcall(vim.api.nvim_buf_clear_namespace, state.response_buf, state.ns_id, 0, -1)
  end
end

--- Close all windows and clean up
function M.close(state)
  if not state then
    return
  end

  M._stop_spinner(state)

  -- Stop any running job
  if state.job_id then
    pcall(vim.fn.jobstop, state.job_id)
    state.job_id = nil
  end

  -- Stop timeout timer
  if state.timeout_timer then
    state.timeout_timer:stop()
    state.timeout_timer:close()
    state.timeout_timer = nil
  end

  -- Delete augroup first to prevent recursive cleanup
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end

  -- Close windows
  local wins = { state.container_win, state.code_win, state.prompt_win, state.response_win }
  for _, win in ipairs(wins) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  -- Clear module-level state
  require("nvim-ask").clear_state()
end

--- Recalculate layout on resize
function M._relayout(state)
  if not state or not state.container_win or not vim.api.nvim_win_is_valid(state.container_win) then
    return
  end

  local layout = compute_layout(state.config)
  state.layout = layout

  -- Update container
  pcall(vim.api.nvim_win_set_config, state.container_win, {
    relative = "editor",
    row = layout.row,
    col = layout.col,
    width = layout.width,
    height = layout.height,
  })

  -- Update code window
  local code_lines = state.context.selection and state.context.selection.lines or { "" }
  local code_height = math.min(#code_lines, math.floor(layout.inner_height * 0.35))
  if not state.context.selection then
    code_height = 1
  end

  if state.code_win and vim.api.nvim_win_is_valid(state.code_win) then
    pcall(vim.api.nvim_win_set_config, state.code_win, {
      relative = "editor",
      row = layout.inner_row,
      col = layout.inner_col,
      width = layout.inner_width,
      height = code_height,
    })
  end

  -- Update prompt window
  local prompt_row = layout.inner_row + code_height + 1
  if state.prompt_win and vim.api.nvim_win_is_valid(state.prompt_win) then
    pcall(vim.api.nvim_win_set_config, state.prompt_win, {
      relative = "editor",
      row = prompt_row,
      col = layout.inner_col,
      width = layout.inner_width,
      height = 3,
    })
  end

  -- Update response window
  state.response_start_row = prompt_row + 3 + 2
  state.response_available_height = layout.inner_row + layout.inner_height - state.response_start_row

  if state.response_win and vim.api.nvim_win_is_valid(state.response_win) then
    local response_height = math.max(state.response_available_height, 3)
    pcall(vim.api.nvim_win_set_config, state.response_win, {
      relative = "editor",
      row = state.response_start_row,
      col = layout.inner_col,
      width = layout.inner_width,
      height = response_height,
    })
  end
end

return M
