local M = {}

--- Build the full prompt combining selected code and user instruction
function M.build_prompt(context, user_prompt)
  local parts = {}

  if context.selection and #context.selection.lines > 0 then
    table.insert(parts, "The user has selected the following code in their editor.")
    table.insert(parts, "They want you to help with it based on their instruction.")
    table.insert(parts, "If your response is a code change, wrap it in a code fence with the appropriate language identifier.")
    table.insert(parts, "If your response is an explanation, just write plain text.")
    table.insert(parts, "")
    table.insert(parts, "--- SELECTED CODE (filetype: " .. (context.filetype or "text") .. ") ---")
    table.insert(parts, table.concat(context.selection.lines, "\n"))
    table.insert(parts, "--- END SELECTED CODE ---")
    table.insert(parts, "")
    table.insert(parts, "User instruction: " .. user_prompt)
  else
    table.insert(parts, user_prompt)
  end

  return table.concat(parts, "\n")
end

--- Send a prompt to the Claude CLI
--- @param prompt string the full prompt text
--- @param config table plugin config
--- @param callbacks table { on_delta: fn(text), on_complete: fn(full_text), on_error: fn(err) }
--- @return number|nil job_id
function M.send(prompt, config, callbacks)
  -- Check claude is available
  if vim.fn.executable("claude") ~= 1 then
    callbacks.on_error("'claude' CLI not found in PATH. Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code")
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

  if config.claude.model then
    table.insert(cmd, "--model")
    table.insert(cmd, config.claude.model)
  end

  -- Partial line buffer for NDJSON parsing
  local partial_line = ""
  local got_result = false

  local function process_line(line)
    if line == "" then
      return
    end

    local ok, obj = pcall(vim.json.decode, line)
    if not ok then
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

  -- Timeout timer
  if config.claude.timeout and config.claude.timeout > 0 then
    local timeout_timer = vim.uv.new_timer()
    timeout_timer:start(config.claude.timeout * 1000, 0, vim.schedule_wrap(function()
      if not got_result then
        pcall(vim.fn.jobstop, job_id)
        callbacks.on_error("Request timed out after " .. config.claude.timeout .. " seconds")
      end
      timeout_timer:stop()
      timeout_timer:close()
    end))
    -- Store on the return so the caller can clean up if needed
    -- We'll return the job_id; the UI stores the timeout timer on state
  end

  return job_id
end

--- Stop a running Claude process
function M.stop(job_id)
  if job_id then
    pcall(vim.fn.jobstop, job_id)
  end
end

return M
