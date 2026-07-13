# nvim-ask

An inline AI code assistant for Neovim, powered by the [Claude CLI](https://docs.anthropic.com/en/docs/claude-code). Select code, ask a question, get a streaming response in a floating overlay — then apply it directly to your buffer.

## Requirements

- Neovim >= 0.9
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated (`claude` in your PATH)

## Health check

Run `:checkhealth nvim-ask` to verify your setup. It reports the Neovim
version, the registered/selected backend (via the backend's own `health()`),
available presets, and which context providers are enabled.

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
  backend = "claude",           -- which backend to use (see "Backends")
  window = {
    width = 0.8,                -- fraction of editor width
    height = 0.8,               -- fraction of editor height
    border = "rounded",         -- border style
    min_width = 40,             -- minimum terminal width to open
    min_height = 15,            -- minimum terminal height to open
  },
  claude = {                    -- options for the "claude" backend
    model = nil,                -- override model (e.g. "sonnet")
    timeout = 120,              -- request timeout in seconds
  },
  confirm_apply = true,         -- preview a diff and confirm before applying
  context = {                   -- extra editor context to include in prompts
    surrounding_lines = 0,      -- N lines above/below the selection (0 = off)
    whole_file = false,         -- include the entire file
    diagnostics = false,        -- include LSP diagnostics for the selection
    git_diff = false,           -- include `git diff` for the file
  },
  presets = {                   -- add or override preset prompt templates
    -- mycheck = "Review this code for security issues.",
  },
})
```

Invalid config values (unknown `backend`, out-of-range window fractions, a
negative `timeout`, a negative `context.surrounding_lines`) are reported via
`vim.notify` and replaced with defaults rather than breaking `setup()`.

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

### Presets

Presets prefill the prompt with a common instruction (you can still edit before
sending). Built-in presets: `explain`, `docs`, `tests`, `fix`, `refactor`,
`optimize`. Add or override them via `config.presets`.

- `:NvimAsk <preset>` — open with that preset (tab-completes preset names)
- `:NvimAskPreset` — choose a preset interactively
- `require("nvim-ask").open_preset("explain", { range = true })` — from Lua

### Follow-up questions (multi-turn)

After a response, the prompt is re-armed for a follow-up. Press `<Tab>` to focus
the prompt, type a follow-up, and `<CR>` to send — the full conversation so far
is included as context. `r` (Retry) re-runs the last turn, replacing it instead
of stacking a duplicate.

### Applying changes

By default (`confirm_apply = true`), pressing `<CR>`/Apply first shows a diff of
your selection vs. the suggested code; press `<CR>`/`y` to accept or `n`/`q` to
cancel. Set `confirm_apply = false` to write immediately. When a response
contains multiple code blocks you're asked which one to apply.

## Keybinds (inside the overlay)

| Key | Context | Action |
|---|---|---|
| `<CR>` | Prompt buffer | Send request / follow-up |
| `<CR>` | Response buffer | Apply code (with diff preview) |
| `y` | Response buffer | Yank response to clipboard |
| `r` | Response buffer | Retry (re-run last turn) |
| `<Tab>` | Any | Cycle focus to next section |
| `<S-Tab>` | Any | Cycle focus to previous section |
| `q` | Any | Close the overlay |

### Keybinds (inside the diff preview)

| Key | Action |
|---|---|
| `<CR>` / `y` | Accept and apply |
| `n` / `q` / `<Esc>` | Cancel |

## How it works

- Invokes `claude` as a child process via `vim.fn.jobstart`
- Streams the response token-by-token using `--output-format stream-json`
- Parses markdown code fences from the response for syntax highlighting and apply/yank
- Disables all Claude tools (`--tools ""`) so you only get text responses

## Backends

The transport layer is abstracted behind a small backend interface, selected
via `config.backend`. The built-in backend is `"claude"`; additional providers
(e.g. OpenAI, Ollama) can be added without touching the UI.

A backend is a Lua module implementing:

```lua
local backend = {
  name = "claude",        -- identifier
  config_key = "claude",  -- key in the user config holding this backend's options

  -- Verify the backend is usable.
  health = function() return true, "message" end,

  -- Start a request. `opts` is config[config_key]; `callbacks` is
  -- { on_delta = fn(text), on_complete = fn(full_text), on_error = fn(err) }.
  -- Returns an opaque `handle` consumed only by `stop`.
  send = function(prompt, opts, callbacks) return handle end,

  -- Cancel a running request (and any timers). Safe to call more than once.
  stop = function(handle) end,
}
```

Register a custom backend before use:

```lua
require("nvim-ask.backends").register("myprovider", require("my.backend"))
require("nvim-ask").setup({ backend = "myprovider", myprovider = { --[[ opts ]] } })
```

The prompt sent to every backend is built by the provider-agnostic
`nvim-ask.prompt` module.

## Development

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (busted
style) and live in `tests/spec/`.

```sh
make test          # run the suite headlessly
make deps          # clone plenary into .tests/ (e.g. on CI or a clean machine)
```

`make test` discovers plenary from `PLENARY_DIR`, a local `.tests/` clone, or an
existing install (lazy.nvim / packer). The suite covers the parser, prompt
builder, presets, context providers, backend registry, diff preview, the health
check, and a multi-turn + apply integration flow driven by a fake backend.

## License

MIT
