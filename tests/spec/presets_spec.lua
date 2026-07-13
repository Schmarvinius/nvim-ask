local presets = require("nvim-ask.presets")

describe("presets", function()
  it("provides built-in defaults", function()
    assert.is_not_nil(presets.get({}, "explain"))
    assert.is_not_nil(presets.get({}, "refactor"))
  end)

  it("lets user config override a default", function()
    assert.equals("custom", presets.get({ presets = { explain = "custom" } }, "explain"))
  end)

  it("lets user config add new presets", function()
    assert.equals("x", presets.get({ presets = { mine = "x" } }, "mine"))
  end)

  it("lists names sorted, including user additions", function()
    local names = presets.names({ presets = { aaa = "x" } })
    assert.equals("aaa", names[1])
    assert.is_truthy(vim.tbl_contains(names, "tests"))
  end)

  it("returns nil for an unknown preset", function()
    assert.is_nil(presets.get({}, "nope"))
    assert.is_nil(presets.get({}, nil))
  end)
end)
