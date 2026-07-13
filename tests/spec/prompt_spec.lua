local prompt = require("nvim-ask.prompt")

describe("prompt.build", function()
  it("returns a bare instruction with no selection/context/history", function()
    assert.equals("hi", prompt.build({ filetype = "lua" }, "hi"))
  end)

  it("includes the selected code and format rules", function()
    local p = prompt.build({ filetype = "lua", selection = { lines = { "local x = 1" } } }, "refactor")
    assert.is_truthy(p:match("SELECTED CODE"))
    assert.is_truthy(p:match("local x = 1"))
    assert.is_truthy(p:match("User instruction: refactor"))
  end)

  it("renders extra context sections", function()
    local ctx = {
      filetype = "lua",
      selection = { lines = { "local x = 1" } },
      extra = { { title = "FULL FILE (a.lua)", lines = { "local x = 1", "print(x)" } } },
    }
    local p = prompt.build(ctx, "explain")
    assert.is_truthy(p:match("FULL FILE %(a%.lua%)"))
    assert.is_truthy(p:match("END FULL FILE %(a%.lua%)"))
    assert.is_truthy(p:match("print%(x%)"))
  end)

  it("renders prior conversation turns", function()
    local p = prompt.build({ filetype = "lua" }, "next", {
      history = {
        { role = "user", text = "first q" },
        { role = "assistant", text = "first a" },
      },
    })
    assert.is_truthy(p:match("CONVERSATION SO FAR"))
    assert.is_truthy(p:match("User: first q"))
    assert.is_truthy(p:match("Assistant: first a"))
    assert.is_truthy(p:match("User instruction: next"))
  end)
end)
