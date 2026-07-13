--- Backend registry and selection.
---
--- A backend is a module implementing:
---   name        : string
---   config_key  : string  -- key in user config holding its options
---   health()    : () -> ok:boolean, msg:string
---   send(prompt, opts, callbacks) -> handle|nil
---   stop(handle)
---
--- Additional backends (OpenAI, Ollama, ...) can be added by calling
--- `require("nvim-ask.backends").register(name, module)` before use, or by
--- adding a module here.
local M = {}

local registry = {
  claude = require("nvim-ask.backends.claude"),
}

--- Register (or override) a backend under the given name.
--- @param name string
--- @param module table backend module implementing the interface
function M.register(name, module)
  registry[name] = module
end

--- List the names of all registered backends.
--- @return string[]
function M.names()
  local names = {}
  for name in pairs(registry) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

--- Get a backend module by name, or nil if not registered.
--- @param name string
--- @return table|nil
function M.get(name)
  return registry[name]
end

--- Resolve the backend selected by the given config.
--- @param config table plugin config (uses config.backend, default "claude")
--- @return table|nil backend, string|nil err
function M.resolve(config)
  local name = (config and config.backend) or "claude"
  local backend = registry[name]
  if not backend then
    return nil, string.format(
      "nvim-ask: unknown backend '%s' (available: %s)",
      tostring(name),
      table.concat(M.names(), ", ")
    )
  end
  return backend, nil
end

--- Extract the backend-specific options table from the config.
--- @param config table plugin config
--- @param backend table backend module
--- @return table opts
function M.opts(config, backend)
  return (config and config[backend.config_key]) or {}
end

return M
