--- Diff preview + confirmation.
---
--- Renders a unified diff between the current selection (old) and the
--- suggested code (new) in a floating window, and asks the user to accept or
--- reject before anything is written to their buffer.
local M = {}

--- Build a unified-diff representation between two line lists.
--- @param old_lines string[]
--- @param new_lines string[]
--- @return string[] diff_lines (may be empty when identical)
function M.unified(old_lines, new_lines)
  local a = table.concat(old_lines, "\n")
  local b = table.concat(new_lines, "\n")
  if a == b then
    return {}
  end
  -- vim.diff needs trailing newlines to treat the last line consistently.
  local diff = vim.diff(a .. "\n", b .. "\n", { ctxlen = 3 })
  if not diff or diff == "" then
    return {}
  end
  return vim.split(diff, "\n", { plain = true, trimempty = true })
end

--- Show a diff preview and invoke on_accept / on_reject based on the user's
--- choice. The preview window manages its own buffer/window lifecycle.
--- @param opts table {
---   old_lines: string[], new_lines: string[], filetype?: string,
---   title?: string, border?: string,
---   on_accept: fun(), on_reject: fun() }
function M.preview(opts)
  local old_lines = opts.old_lines or {}
  local new_lines = opts.new_lines or {}
  local diff_lines = M.unified(old_lines, new_lines)

  local body
  local ft
  if #diff_lines == 0 then
    body = { "(no changes — suggested code is identical to the selection)" }
    ft = nil
  else
    body = diff_lines
    ft = "diff"
  end

  local editor_w = vim.o.columns
  local editor_h = vim.o.lines - vim.o.cmdheight - 1
  local width = math.min(math.max(60, math.floor(editor_w * 0.7)), editor_w - 4)
  local height = math.min(math.max(#body + 1, 8), math.floor(editor_h * 0.7))
  local row = math.floor((editor_h - height) / 2)
  local col = math.floor((editor_w - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, body)
  if ft then
    vim.bo[buf].filetype = ft
  end
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = opts.border or "rounded",
    title = opts.title or " Preview changes ",
    title_pos = "center",
    footer = " <CR>/y Apply  |  n/q Cancel ",
    footer_pos = "center",
    zindex = 200,
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  local closed = false
  local function finish(accepted)
    if closed then
      return
    end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if accepted then
      if opts.on_accept then
        opts.on_accept()
      end
    else
      if opts.on_reject then
        opts.on_reject()
      end
    end
  end

  local function map(lhs, accepted)
    vim.keymap.set("n", lhs, function()
      finish(accepted)
    end, { buffer = buf, nowait = true })
  end

  map("<CR>", true)
  map("y", true)
  map("n", false)
  map("q", false)
  map("<Esc>", false)

  return { buf = buf, win = win }
end

return M
