--- Preset prompt templates for common actions.
---
--- A preset maps a short name to an instruction string that is prefilled into
--- the prompt buffer when the overlay opens (the user can still edit or extend
--- it before sending). Users can add or override presets via
--- config.presets = { name = "instruction", ... }.
local M = {}

--- Built-in presets.
M.defaults = {
  explain = "Explain what this code does, step by step.",
  docs = "Add clear documentation comments/docstrings to this code. Return the full updated code.",
  tests = "Write thorough unit tests for this code.",
  fix = "Find and fix any bugs or issues in this code. Return the corrected code.",
  refactor = "Refactor this code to improve readability and maintainability without changing its behavior.",
  optimize = "Optimize this code for performance where reasonable, and explain the key changes.",
}

--- Resolve the effective preset table from config (defaults + user overrides).
--- @param config table plugin config
--- @return table<string,string>
function M.resolve(config)
  local presets = vim.deepcopy(M.defaults)
  if config and type(config.presets) == "table" then
    for name, instruction in pairs(config.presets) do
      presets[name] = instruction
    end
  end
  return presets
end

--- Sorted list of preset names for completion/menus.
--- @param config table plugin config
--- @return string[]
function M.names(config)
  local names = {}
  for name in pairs(M.resolve(config)) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

--- Look up a preset instruction by name.
--- @param config table plugin config
--- @param name string
--- @return string|nil
function M.get(config, name)
  if not name then
    return nil
  end
  return M.resolve(config)[name]
end

return M
