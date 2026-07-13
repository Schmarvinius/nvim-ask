local backends = require("nvim-ask.backends")
local nvim_ask = require("nvim-ask")

-- A fake backend that records prompts and completes synchronously (scheduled).
local captured
local function register_fake()
  captured = { prompts = {} }
  backends.register("fake", {
    name = "fake",
    config_key = "fake",
    health = function() return true, "ok" end,
    send = function(prompt, _opts, cb)
      table.insert(captured.prompts, prompt)
      vim.schedule(function()
        cb.on_delta("Here is the fix:\n")
        cb.on_complete("Here is the fix:\n```lua\nreturn 42\n```")
      end)
      return { id = 1 }
    end,
    stop = function() end,
  })
end

local function wait_idle(state)
  vim.wait(1000, function()
    return state.sending == false
  end)
end

describe("multi-turn conversation + apply", function()
  local state, buf

  before_each(function()
    register_fake()
    nvim_ask.setup({ backend = "fake", confirm_apply = false, fake = {} })

    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local a = 1", "return a" })
    vim.api.nvim_set_current_buf(buf)

    local context = {
      buf = buf,
      win = vim.api.nvim_get_current_win(),
      filetype = "lua",
      selection = { start_line = 1, end_line = 2, lines = { "local a = 1", "return a" }, mode = "V" },
      extra = {},
    }
    state = require("nvim-ask.ui").open(context, nvim_ask.config, { initial_prompt = "fix it" })
    assert.is_not_nil(state)
  end)

  after_each(function()
    pcall(require("nvim-ask.ui").close, state)
  end)

  it("prefills the prompt from initial_prompt", function()
    assert.equals("fix it", vim.api.nvim_buf_get_lines(state.prompt_buf, 0, -1, false)[1])
  end)

  it("records the turn, parses code, and re-arms the prompt", function()
    local ui = require("nvim-ask.ui")
    ui._send_prompt(state)
    wait_idle(state)

    assert.is_false(state.sending)
    assert.equals(2, #state.messages)
    assert.equals("user", state.messages[1].role)
    assert.equals("fix it", state.messages[1].text)
    assert.equals("return 42", state.parsed_code)
    -- follow-up prompt re-armed
    assert.is_true(vim.bo[state.prompt_buf].modifiable)
    assert.equals("", vim.api.nvim_buf_get_lines(state.prompt_buf, 0, -1, false)[1])
    assert.is_falsy(captured.prompts[1]:match("CONVERSATION SO FAR"))
  end)

  it("includes prior turns in a follow-up prompt", function()
    local ui = require("nvim-ask.ui")
    ui._send_prompt(state)
    wait_idle(state)

    vim.api.nvim_buf_set_lines(state.prompt_buf, 0, -1, false, { "now add a comment" })
    ui._send_prompt(state)
    wait_idle(state)

    assert.equals(4, #state.messages)
    assert.is_truthy(captured.prompts[2]:match("CONVERSATION SO FAR"))
    assert.is_truthy(captured.prompts[2]:match("User: fix it"))
    assert.is_truthy(captured.prompts[2]:match("return 42"))
  end)

  it("retry replaces the last turn instead of stacking it", function()
    local ui = require("nvim-ask.ui")
    ui._send_prompt(state)
    wait_idle(state)
    vim.api.nvim_buf_set_lines(state.prompt_buf, 0, -1, false, { "now add a comment" })
    ui._send_prompt(state)
    wait_idle(state)

    require("nvim-ask.actions").retry(state)
    wait_idle(state)

    assert.equals(4, #state.messages)
    assert.equals("now add a comment", state.messages[3].text)
  end)

  it("apply writes the suggested code to the original buffer", function()
    local ui = require("nvim-ask.ui")
    ui._send_prompt(state)
    wait_idle(state)

    require("nvim-ask.actions").apply(state)
    local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals(1, #result)
    assert.equals("return 42", result[1])
  end)
end)
