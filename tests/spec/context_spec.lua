local context = require("nvim-ask.context")

local function make_editor()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "l1", "l2", "l3", "l4", "l5", "l6", "l7" })
  return {
    buf = buf,
    win = 0,
    filetype = "lua",
    selection = { start_line = 3, end_line = 4, lines = { "l3", "l4" } },
  }
end

describe("context.gather", function()
  it("returns nothing when no providers are enabled", function()
    assert.equals(0, #context.gather(make_editor(), {}))
  end)

  it("includes surrounding lines clamped to the buffer", function()
    local secs = context.gather(make_editor(), { surrounding_lines = 2 })
    assert.equals(1, #secs)
    assert.is_truthy(secs[1].title:match("SURROUNDING"))
    assert.equals("l1", secs[1].lines[1])
    assert.equals("l6", secs[1].lines[#secs[1].lines])
  end)

  it("does not add surrounding lines without a selection", function()
    local editor = make_editor()
    editor.selection = nil
    assert.equals(0, #context.gather(editor, { surrounding_lines = 3 }))
  end)

  it("includes the whole file", function()
    local secs = context.gather(make_editor(), { whole_file = true })
    assert.equals(1, #secs)
    assert.equals(7, #secs[1].lines)
    assert.is_truthy(secs[1].title:match("FULL FILE"))
  end)

  it("combines multiple providers", function()
    local secs = context.gather(make_editor(), { surrounding_lines = 1, whole_file = true })
    assert.equals(2, #secs)
  end)
end)
