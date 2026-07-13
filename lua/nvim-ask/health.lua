--- Health check for `:checkhealth nvim-ask`.
local M = {}

-- Support both the modern (vim.health.start) and legacy (report_*) APIs.
local health = vim.health or {}
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error_ = health.error or health.report_error
local info = health.info or health.report_info

function M.check()
  local nvim_ask = require("nvim-ask")
  local backends = require("nvim-ask.backends")
  local config = nvim_ask.config

  -- Neovim version -----------------------------------------------------------
  start("nvim-ask: Neovim")
  if vim.fn.has("nvim-0.9") == 1 then
    ok("Neovim " .. tostring(vim.version()))
  else
    error_("Neovim >= 0.9 is required")
  end

  -- Backend ------------------------------------------------------------------
  start("nvim-ask: backend")
  info("Registered backends: " .. table.concat(backends.names(), ", "))
  info("Selected backend: " .. tostring(config.backend))

  local backend, err = backends.resolve(config)
  if not backend then
    error_(err or ("Backend '" .. tostring(config.backend) .. "' is not registered"))
  else
    if type(backend.health) == "function" then
      local healthy, msg = backend.health()
      if healthy then
        ok(string.format("Backend '%s': %s", backend.name, msg or "ok"))
      else
        error_(string.format("Backend '%s': %s", backend.name, msg or "unavailable"))
      end
    else
      warn(string.format("Backend '%s' does not implement health()", backend.name))
    end
  end

  -- Presets ------------------------------------------------------------------
  start("nvim-ask: presets")
  local names = require("nvim-ask.presets").names(config)
  if #names > 0 then
    ok("Presets available: " .. table.concat(names, ", "))
  else
    warn("No presets configured")
  end

  -- Context providers --------------------------------------------------------
  start("nvim-ask: context")
  local ctx = config.context or {}
  local enabled = {}
  if (ctx.surrounding_lines or 0) > 0 then
    table.insert(enabled, "surrounding_lines=" .. ctx.surrounding_lines)
  end
  if ctx.whole_file then
    table.insert(enabled, "whole_file")
  end
  if ctx.diagnostics then
    table.insert(enabled, "diagnostics")
  end
  if ctx.git_diff then
    table.insert(enabled, "git_diff")
  end
  if #enabled > 0 then
    info("Enabled context providers: " .. table.concat(enabled, ", "))
  else
    info("No extra context providers enabled")
  end
  if ctx.git_diff and vim.fn.executable("git") ~= 1 then
    warn("context.git_diff is enabled but 'git' was not found in PATH")
  end
end

return M
