local diff = require("nvim-ask.diff")

describe("diff.unified", function()
  it("returns an empty result for identical content", function()
    assert.equals(0, #diff.unified({ "a", "b" }, { "a", "b" }))
  end)

  it("produces a unified diff for changed content", function()
    local d = diff.unified({ "a", "b", "c" }, { "a", "B", "c" })
    assert.is_true(#d > 0)
    local joined = table.concat(d, "\n")
    assert.is_truthy(joined:match("%-b"))
    assert.is_truthy(joined:match("%+B"))
  end)
end)

describe("diff.preview", function()
  it("opens a window, and accept fires on_accept then closes", function()
    local accepted, rejected = false, false
    local h = diff.preview({
      old_lines = { "a" },
      new_lines = { "b" },
      on_accept = function() accepted = true end,
      on_reject = function() rejected = true end,
    })
    assert.is_true(vim.api.nvim_win_is_valid(h.win))
    assert.equals("diff", vim.bo[h.buf].filetype)
    vim.api.nvim_set_current_win(h.win)
    vim.api.nvim_feedkeys("y", "x", false)
    assert.is_true(accepted)
    assert.is_false(rejected)
    assert.is_false(vim.api.nvim_win_is_valid(h.win))
  end)

  it("reject fires on_reject then closes", function()
    local accepted, rejected = false, false
    local h = diff.preview({
      old_lines = { "a" },
      new_lines = { "b" },
      on_accept = function() accepted = true end,
      on_reject = function() rejected = true end,
    })
    vim.api.nvim_set_current_win(h.win)
    vim.api.nvim_feedkeys("n", "x", false)
    assert.is_true(rejected)
    assert.is_false(accepted)
    assert.is_false(vim.api.nvim_win_is_valid(h.win))
  end)

  it("shows a no-changes message for identical content", function()
    local h = diff.preview({
      old_lines = { "same" },
      new_lines = { "same" },
      on_accept = function() end,
      on_reject = function() end,
    })
    local body = vim.api.nvim_buf_get_lines(h.buf, 0, -1, false)
    assert.is_truthy(body[1]:match("no changes"))
    vim.api.nvim_win_close(h.win, true)
  end)
end)
