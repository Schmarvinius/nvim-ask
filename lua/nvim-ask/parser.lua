local M = {}

--- Match an opening code fence, capturing the language (may be empty).
--- Accepts languages with non-word chars like `c++`, `c#`, `objective-c`,
--- and tolerates trailing info strings after the language token.
--- @param line string
--- @return string|nil lang the captured language, or nil if not a fence
local function match_fence_open(line)
  -- Capture the first token after the backticks; allow a trailing info string.
  local lang = line:match("^```([%w#+.-]*)")
  if lang == nil then
    return nil
  end
  if lang == "" then
    return nil, true -- fence with no language
  end
  return lang
end

--- Whether a line closes a code fence.
--- @param line string
--- @return boolean
local function is_fence_close(line)
  return line:match("^```%s*$") ~= nil
end

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
      local lang, no_lang = match_fence_open(line)
      if lang then
        in_block = true
        current_lang = lang
        current_lines = {}
      elseif no_lang then
        -- Code fence without language
        in_block = true
        current_lang = nil
        current_lines = {}
      end
    else
      if is_fence_close(line) then
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

--- Split a response into an explanation part and its code block(s).
--- All prose (before, between, and after fences) is collected into `text`.
--- Every fenced code block is collected into `blocks` (in order). For
--- backward compatibility, `code`/`lang` mirror the FIRST block.
--- @param text string the full response text
--- @return table { text: string|nil, code: string|nil, lang: string|nil, blocks: table[] }
function M.split_response(text)
  local lines = vim.split(text or "", "\n", { plain = true })

  local prose = {}
  local blocks = {}
  local code_lines = {}
  local current_lang = nil
  local in_code = false

  for _, line in ipairs(lines) do
    if not in_code then
      local lang, no_lang = match_fence_open(line)
      if lang then
        in_code = true
        current_lang = lang
        code_lines = {}
      elseif no_lang then
        in_code = true
        current_lang = nil
        code_lines = {}
      else
        table.insert(prose, line)
      end
    else
      if is_fence_close(line) then
        table.insert(blocks, {
          lang = current_lang,
          code = table.concat(code_lines, "\n"),
        })
        in_code = false
        current_lang = nil
        code_lines = {}
      else
        table.insert(code_lines, line)
      end
    end
  end

  -- Unterminated fence: still capture what we have as a block.
  if in_code and #code_lines > 0 then
    table.insert(blocks, {
      lang = current_lang,
      code = table.concat(code_lines, "\n"),
    })
  end

  local result = {
    text = nil,
    code = nil,
    lang = nil,
    blocks = blocks,
  }

  local prose_str = vim.trim(table.concat(prose, "\n"))
  if prose_str ~= "" then
    result.text = prose_str
  end

  if #blocks > 0 then
    result.code = blocks[1].code
    result.lang = blocks[1].lang
  end

  return result
end

return M
