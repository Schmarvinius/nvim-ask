# nvim-ask

An inline AI code assistant for Neovim, powered by the [Claude CLI](https://docs.anthropic.com/en/docs/claude-code). Select code, ask a question, get a streaming response in a floating overlay — then apply it directly to your buffer.

## Requirements

- Neovim >= 0.9
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated (`claude` in your PATH)

## Installation

### lazy.nvim

```lua
{
  "your-username/nvim-ask",
  config = function()
    require("nvim-ask").setup()
  end,
}
```

### Local development

```lua
{
  dir = "~/path/to/nvim-ask",
  config = function()
    require("nvim-ask").setup()
  end,
}
```

## Configuration

```lua
require("nvim-ask").setup({
  keybind = "<leader>ai",       -- keybind for visual + normal mode
  window = {
    width = 0.8,                -- fraction of editor width
    height = 0.8,               -- fraction of editor height
    border = "rounded",         -- border style
    min_width = 40,             -- minimum terminal width to open
    min_height = 15,            -- minimum terminal height to open
  },
  claude = {
    model = nil,                -- override model (e.g. "sonnet")
    max_tokens = nil,           -- max output tokens
    timeout = 120,              -- request timeout in seconds
  },
})
```

## Usage

### With a code selection

1. Visually select code (`V`, `v`, or `<C-v>`)
2. Press `<leader>ai` (or your configured keybind)
3. Type your instruction in the prompt (e.g. "refactor this to use async/await")
4. Press `<CR>` to send
5. Press `<CR>` in the response to replace the original selection

### Without a selection

1. Press `<leader>ai` in normal mode
2. Type a general question
3. Press `<CR>` to send

You can also use the `:NvimAsk` command directly.

## Keybinds (inside the overlay)

| Key | Context | Action |
|---|---|---|
| `<CR>` | Prompt buffer | Send request |
| `<CR>` | Response buffer | Apply code to original buffer |
| `y` | Response buffer | Yank response to clipboard |
| `r` | Response buffer | Retry (re-send same prompt) |
| `<Tab>` | Any | Cycle focus to next section |
| `<S-Tab>` | Any | Cycle focus to previous section |
| `q` | Any | Close the overlay |

## How it works

- Invokes `claude` as a child process via `vim.fn.jobstart`
- Streams the response token-by-token using `--output-format stream-json`
- Parses markdown code fences from the response for syntax highlighting and apply/yank
- Disables all Claude tools (`--tools ""`) so you only get text responses

## License

MIT
