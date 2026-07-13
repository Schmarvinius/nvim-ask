local M = {}

--- Build the full prompt combining selected code and user instruction.
--- This is provider-agnostic: every backend receives the same prompt text.
--- @param context table { filetype, selection }
--- @param user_prompt string the user's instruction
--- @return string prompt
function M.build(context, user_prompt)
  local parts = {}

  if context.selection and #context.selection.lines > 0 then
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
    table.insert(parts, "")
    table.insert(parts, "User instruction: " .. user_prompt)
  else
    table.insert(parts, user_prompt)
  end

  return table.concat(parts, "\n")
end

return M
