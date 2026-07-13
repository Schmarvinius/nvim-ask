--- Claude CLI backend.
---
--- Implements the nvim-ask backend interface:
---   name        : string identifier
---   config_key  : key in the user config holding this backend's options
---   health()    : () -> ok:boolean, msg:string
---   send(prompt, opts, callbacks) -> handle|nil
---   stop(handle): cancels the running request and its timeout timer
---
--- `opts` is the backend-specific config table (see config.claude), e.g.
---   { model = "sonnet"|nil, timeout = 120 }
---
--- `callbacks` is { on_delta = fn(text), on_complete = fn(full_text), on_error = fn(err) }
--- A `handle` is an opaque table { job_id, timer } consumed only by stop().
local M = {}

M.name = "claude"
M.config_key = "claude"

--- Verify the backend is usable.
--- @return boolean ok, string msg
function M.health()
  if vim.fn.executable("claude") ~= 1 then
    return false, "'claude' CLI not found in PATH. Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code"
  end
  return true, "claude CLI found in PATH"
end

--- Safely stop and close a libuv timer.
function M.stop_timer(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

--- @param prompt string the full prompt text
--- @param opts table backend options { model, timeout }
--- @param callbacks table { on_delta, on_complete, on_error }
--- @return table|nil handle
function M.send(prompt, opts, callbacks)
  opts = opts or {}

  local ok, msg = M.health()
  if not ok then
    callbacks.on_error(msg)
    return nil
  end

  local cmd = {
    "claude",
    "-p", prompt,
    "--output-format", "stream-json",
    "--verbose",
    "--include-partial-messages",
    "--max-turns", "1",
    "--no-session-persistence",
    "--tools", "",
  }

  if opts.model then
    table.insert(cmd, "--model")
    table.insert(cmd, opts.model)
  end

  -- Partial line buffer for NDJSON parsing
  local partial_line = ""
  local got_result = false

  local function process_line(line)
    if line == "" then
      return
    end

    local decoded, obj = pcall(vim.json.decode, line)
    if not decoded then
      return
    end

    if obj.type == "stream_event"
        and obj.event
        and obj.event.type == "content_block_delta"
        and obj.event.delta
        and obj.event.delta.type == "text_delta" then
      callbacks.on_delta(obj.event.delta.text)
    elseif obj.type == "result" then
      got_result = true
      if obj.is_error then
        callbacks.on_error(obj.result or "Claude returned an error")
      else
        callbacks.on_complete(obj.result or "")
      end
    end
  end

  local stderr_chunks = {}

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    stderr_buffered = false,

    on_stdout = function(_, data, _)
      if not data then
        return
      end
      for i, chunk in ipairs(data) do
        if i == 1 then
          partial_line = partial_line .. chunk
        else
          process_line(partial_line)
          partial_line = chunk
        end
      end
    end,

    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_chunks, line)
          end
        end
      end
    end,

    on_exit = function(_, exit_code, _)
      -- Process any remaining partial line
      if partial_line ~= "" then
        process_line(partial_line)
        partial_line = ""
      end

      if not got_result then
        local err_msg = "Claude process exited"
        if exit_code ~= 0 then
          err_msg = err_msg .. " with code " .. exit_code
        end
        if #stderr_chunks > 0 then
          err_msg = err_msg .. ": " .. table.concat(stderr_chunks, "\n")
        end
        vim.schedule(function()
          callbacks.on_error(err_msg)
        end)
      end
    end,
  })

  if job_id <= 0 then
    callbacks.on_error("Failed to start claude process (job_id=" .. tostring(job_id) .. ")")
    return nil
  end

  -- Timeout timer. Stored on the handle so it can be cancelled early when a
  -- result arrives (or when the overlay is closed) instead of leaking.
  local timeout_timer = nil
  local timeout = opts.timeout
  if timeout and timeout > 0 then
    timeout_timer = vim.uv.new_timer()
    timeout_timer:start(timeout * 1000, 0, vim.schedule_wrap(function()
      if not got_result then
        pcall(vim.fn.jobstop, job_id)
        callbacks.on_error("Request timed out after " .. timeout .. " seconds")
      end
      M.stop_timer(timeout_timer)
    end))
  end

  return { job_id = job_id, timer = timeout_timer }
end

--- Cancel a running request and its timeout timer. Safe to call multiple times.
--- @param handle table|nil
function M.stop(handle)
  if not handle then
    return
  end
  if handle.job_id then
    pcall(vim.fn.jobstop, handle.job_id)
  end
  M.stop_timer(handle.timer)
end

return M
