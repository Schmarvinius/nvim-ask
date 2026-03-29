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

return M
