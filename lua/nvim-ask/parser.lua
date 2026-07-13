local M = {}

--- Extract code blocks from markdown-formatted text
--- @param text string the full response text
--- @return table[] list of { lang: string|nil, code: string }
function M.extract_code_blocks(text)
  local blocks = {}
  local lines = vim.split(text, "\n", { plain = true })
  local in_block = false
  local current_lang = nil
  local current_lines = {}

  for _, line in ipairs(lines) do
    if not in_block then
      local lang = line:match("^```(%w+)%s*$")
      if lang then
        in_block = true
        current_lang = lang
        current_lines = {}
      elseif line:match("^```%s*$") then
        -- Code fence without language
        in_block = true
        current_lang = nil
        current_lines = {}
      end
    else
      if line:match("^```%s*$") then
        -- End of code block
        table.insert(blocks, {
          lang = current_lang,
          code = table.concat(current_lines, "\n"),
        })
        in_block = false
        current_lang = nil
        current_lines = {}
      else
        table.insert(current_lines, line)
      end
    end
  end

  return blocks
end

--- Get the primary (first) code block's code, suitable for applying
--- @param text string the full response text
--- @return string|nil code, string|nil lang
function M.get_primary_code(text)
  local blocks = M.extract_code_blocks(text)
  if #blocks > 0 then
    return blocks[1].code, blocks[1].lang
  end
  return nil, nil
end

--- Split a response into an explanation part and a code part.
--- Everything before the first code fence becomes the explanation `text`.
--- The contents of the first fence becomes `code` (with its `lang`).
--- Any prose after the fence is appended to `text` as a trailing note.
--- @param text string the full response text
--- @return table { text: string|nil, code: string|nil, lang: string|nil }
function M.split_response(text)
  local lines = vim.split(text or "", "\n", { plain = true })

  local before = {}
  local after = {}
  local code_lines = {}
  local lang = nil
  local state = "before" -- before | in_code | after

  for _, line in ipairs(lines) do
    if state == "before" then
      local l = line:match("^```(%w+)%s*$")
      if l then
        state = "in_code"
        lang = l
      elseif line:match("^```%s*$") then
        state = "in_code"
        lang = nil
      else
        table.insert(before, line)
      end
    elseif state == "in_code" then
      if line:match("^```%s*$") then
        state = "after"
      else
        table.insert(code_lines, line)
      end
    else -- after
      table.insert(after, line)
    end
  end

  -- Build the explanation text from before + after prose.
  local text_parts = {}
  local before_str = vim.trim(table.concat(before, "\n"))
  if before_str ~= "" then
    table.insert(text_parts, before_str)
  end
  local after_str = vim.trim(table.concat(after, "\n"))
  if after_str ~= "" then
    table.insert(text_parts, after_str)
  end

  local result = {
    text = nil,
    code = nil,
    lang = lang,
  }

  if #text_parts > 0 then
    result.text = table.concat(text_parts, "\n\n")
  end

  -- Only treat as code if we actually closed (or opened) a fence and captured content.
  if state ~= "before" and #code_lines > 0 then
    result.code = table.concat(code_lines, "\n")
  end

  return result
end

return M
