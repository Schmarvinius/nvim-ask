local backends = require("nvim-ask.backends")

describe("backends registry", function()
  it("has the built-in claude backend", function()
    assert.is_not_nil(backends.get("claude"))
    assert.is_truthy(vim.tbl_contains(backends.names(), "claude"))
  end)

  it("resolves the default backend to claude", function()
    local b = backends.resolve({})
    assert.equals("claude", b.name)
  end)

  it("resolves an explicit backend", function()
    local b = backends.resolve({ backend = "claude" })
    assert.equals("claude", b.name)
  end)

  it("errors for an unknown backend", function()
    local b, err = backends.resolve({ backend = "nope" })
    assert.is_nil(b)
    assert.is_truthy(err:match("unknown backend"))
  end)

  it("extracts backend-specific opts via config_key", function()
    local b = backends.resolve({})
    local opts = backends.opts({ claude = { model = "sonnet", timeout = 42 } }, b)
    assert.equals("sonnet", opts.model)
    assert.equals(42, opts.timeout)
  end)

  it("allows registering a custom backend", function()
    local fake = {
      name = "fake",
      config_key = "fake",
      health = function() return true, "ok" end,
      send = function() end,
      stop = function() end,
    }
    backends.register("fake", fake)
    assert.equals("fake", backends.resolve({ backend = "fake" }).name)
  end)
end)

describe("claude backend interface", function()
  local claude = require("nvim-ask.backends.claude")

  it("implements the expected functions", function()
    for _, fn in ipairs({ "health", "send", "stop", "stop_timer" }) do
      assert.equals("function", type(claude[fn]))
    end
    assert.equals("claude", claude.name)
    assert.equals("claude", claude.config_key)
  end)

  it("health returns a boolean and a string", function()
    local ok, msg = claude.health()
    assert.equals("boolean", type(ok))
    assert.equals("string", type(msg))
  end)

  it("stop is safe on nil and partial handles", function()
    assert.has_no.errors(function()
      claude.stop(nil)
      claude.stop({})
      claude.stop_timer(nil)
    end)
  end)
end)
