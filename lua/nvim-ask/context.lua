--- Context providers.
---
--- Gathers optional extra context from the user's editor to enrich the prompt
--- sent to the backend. Each enabled provider contributes a "section"
--- { title = string, lines = string[] } which the prompt builder renders.
---
--- All gathering happens against the ORIGINAL buffer/window captured when the
--- overlay opens, so it must be called while that buffer is still valid.
local M = {}

--- Default (all-off) context configuration.
M.defaults = {
  surrounding_lines = 0, -- N lines of context above/below the selection (0 = off)
  whole_file = false,    -- include the entire file
  diagnostics = false,   -- include LSP diagnostics for the selection/buffer
  git_diff = false,      -- include `git diff` for the file
}

--- Clamp a line number into the valid 1..count range.
local function clamp(n, lo, hi)
  return math.max(lo, math.min(n, hi))
end

--- Surrounding lines above and below the selection.
--- @return table|nil section
local function provider_surrounding(editor, n)
  if not n or n <= 0 or not editor.selection then
    return nil
  end
  if not vim.api.nvim_buf_is_valid(editor.buf) then
    return nil
  end
  local total = vim.api.nvim_buf_line_count(editor.buf)
  local sel = editor.selection
  local from = clamp(sel.start_line - n, 1, total)
  local to = clamp(sel.end_line + n, 1, total)
  local lines = vim.api.nvim_buf_get_lines(editor.buf, from - 1, to, false)
  if #lines == 0 then
    return nil
  end
  return {
    title = string.format("SURROUNDING CONTEXT (lines %d-%d)", from, to),
    lines = lines,
  }
end

--- The entire file contents.
--- @return table|nil section
local function provider_whole_file(editor)
  if not vim.api.nvim_buf_is_valid(editor.buf) then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(editor.buf, 0, -1, false)
  if #lines == 0 then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(editor.buf)
  if name == "" then
    name = "[No Name]"
  else
    name = vim.fn.fnamemodify(name, ":.")
  end
  return {
    title = "FULL FILE (" .. name .. ")",
    lines = lines,
  }
end

--- LSP / diagnostic messages. Restricted to the selection range when present,
--- otherwise the whole buffer.
--- @return table|nil section
local function provider_diagnostics(editor)
  if not vim.diagnostic or not vim.api.nvim_buf_is_valid(editor.buf) then
    return nil
  end
  local diags = vim.diagnostic.get(editor.buf)
  if not diags or #diags == 0 then
    return nil
  end

  local sev_name = {
    [vim.diagnostic.severity.ERROR] = "ERROR",
    [vim.diagnostic.severity.WARN] = "WARN",
    [vim.diagnostic.severity.INFO] = "INFO",
    [vim.diagnostic.severity.HINT] = "HINT",
  }

  local from, to
  if editor.selection then
    from = editor.selection.start_line - 1
    to = editor.selection.end_line - 1
  end

  local lines = {}
  for _, d in ipairs(diags) do
    local in_range = true
    if from then
      in_range = d.lnum >= from and d.lnum <= to
    end
    if in_range then
      local msg = (d.message or ""):gsub("\n", " ")
      table.insert(lines, string.format(
        "line %d [%s] %s",
        d.lnum + 1,
        sev_name[d.severity] or "MSG",
        msg
      ))
    end
  end

  if #lines == 0 then
    return nil
  end
  return { title = "DIAGNOSTICS", lines = lines }
end

--- `git diff` for the file containing the buffer.
--- @return table|nil section
local function provider_git_diff(editor)
  if not vim.api.nvim_buf_is_valid(editor.buf) then
    return nil
  end
  local path = vim.api.nvim_buf_get_name(editor.buf)
  if path == "" or vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  if vim.fn.executable("git") ~= 1 then
    return nil
  end

  local dir = vim.fn.fnamemodify(path, ":h")
  local out = vim.fn.systemlist({ "git", "-C", dir, "diff", "--no-color", "--", path })
  if vim.v.shell_error ~= 0 or not out or #out == 0 then
    return nil
  end
  return { title = "GIT DIFF", lines = out }
end

--- Gather all enabled context sections for the given editor context.
--- @param editor table { buf, win, filetype, selection }
--- @param cfg table context config (see M.defaults)
--- @return table[] sections list of { title, lines }
function M.gather(editor, cfg)
  cfg = cfg or {}
  local sections = {}

  local function add(section)
    if section and section.lines and #section.lines > 0 then
      table.insert(sections, section)
    end
  end

  add(provider_surrounding(editor, cfg.surrounding_lines))
  if cfg.whole_file then
    add(provider_whole_file(editor))
  end
  if cfg.diagnostics then
    add(provider_diagnostics(editor))
  end
  if cfg.git_diff then
    add(provider_git_diff(editor))
  end

  return sections
end

return M
