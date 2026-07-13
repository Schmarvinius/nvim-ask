if vim.g.loaded_nvim_ask then
  return
end
vim.g.loaded_nvim_ask = true

-- :NvimAsk [preset]
-- With no argument, opens the assistant (using the current selection when
-- invoked with a range). With a preset name, prefills that preset's prompt.
vim.api.nvim_create_user_command("NvimAsk", function(opts)
  local range = opts.range > 0
  local name = vim.trim(opts.args or "")
  if name ~= "" then
    require("nvim-ask").open_preset(name, { range = range })
  else
    require("nvim-ask").open({ range = range })
  end
end, {
  range = true,
  nargs = "?",
  desc = "Open nvim-ask AI assistant (optionally with a preset)",
  complete = function(arg_lead)
    local names = require("nvim-ask").preset_names()
    return vim.tbl_filter(function(n)
      return n:find(arg_lead, 1, true) == 1
    end, names)
  end,
})

-- :NvimAskPreset — always choose a preset interactively.
vim.api.nvim_create_user_command("NvimAskPreset", function(opts)
  require("nvim-ask").open_preset(nil, { range = opts.range > 0 })
end, {
  range = true,
  desc = "Open nvim-ask with a preset chosen interactively",
})
