local M = {}

--- Render extra context sections (from nvim-ask.context) into prompt lines.
--- @param parts string[] accumulator
--- @param sections table[] list of { title, lines }
local function append_context_sections(parts, sections)
  if not sections or #sections == 0 then
    return
  end
  for _, section in ipairs(sections) do
    table.insert(parts, "")
    table.insert(parts, "--- " .. section.title .. " ---")
    for _, line in ipairs(section.lines) do
      table.insert(parts, line)
    end
    table.insert(parts, "--- END " .. section.title .. " ---")
  end
end

--- Render prior conversation turns so the backend has the full transcript.
--- @param parts string[] accumulator
--- @param history table[] list of { role = "user"|"assistant", text = string }
local function append_history(parts, history)
  if not history or #history == 0 then
    return
  end
  table.insert(parts, "")
  table.insert(parts, "--- CONVERSATION SO FAR ---")
  for _, turn in ipairs(history) do
    local label = turn.role == "assistant" and "Assistant" or "User"
    table.insert(parts, label .. ": " .. (turn.text or ""))
  end
  table.insert(parts, "--- END CONVERSATION ---")
end

--- Build the full prompt combining selected code, extra context, prior
--- conversation turns, and the user's instruction. Provider-agnostic: every
--- backend receives the same prompt text.
--- @param context table { filetype, selection, extra? }
---   `extra` is an optional list of context sections { title, lines }.
--- @param user_prompt string the user's instruction
--- @param opts table|nil { history = table[] } prior turns (excluding current)
--- @return string prompt
function M.build(context, user_prompt, opts)
  opts = opts or {}
  local parts = {}
  local has_selection = context.selection and #context.selection.lines > 0

  if has_selection then
    table.insert(parts, "The user has selected the following code in their editor.")
    table.insert(parts, "They want you to help with it based on their instruction.")
    table.insert(parts, "")
    table.insert(parts, "Response format rules (follow strictly):")
    table.insert(parts, "1. Write any explanation as plain text FIRST, before any code.")
    table.insert(parts, "2. If you are suggesting a code change, put ALL of the replacement code in exactly ONE fenced code block using the appropriate language identifier, like ```" .. (context.filetype or "text") .. " ... ```.")
    table.insert(parts, "3. Do not split the code across multiple fenced blocks, and do not add any prose after the code block.")
    table.insert(parts, "4. If you have no code to suggest (explanation only), do not include any code fence at all.")
    table.insert(parts, "")
    table.insert(parts, "--- SELECTED CODE (filetype: " .. (context.filetype or "text") .. ") ---")
    table.insert(parts, table.concat(context.selection.lines, "\n"))
    table.insert(parts, "--- END SELECTED CODE ---")
  end

  -- Extra editor context (surrounding lines, whole file, diagnostics, git diff).
  append_context_sections(parts, context.extra)

  -- Prior conversation turns (multi-turn follow-ups).
  append_history(parts, opts.history)

  if has_selection or (context.extra and #context.extra > 0) or (opts.history and #opts.history > 0) then
    table.insert(parts, "")
    table.insert(parts, "User instruction: " .. user_prompt)
  else
    table.insert(parts, user_prompt)
  end

  return table.concat(parts, "\n")
end

return M
