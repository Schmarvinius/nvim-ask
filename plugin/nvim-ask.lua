if vim.g.loaded_nvim_ask then
  return
end
vim.g.loaded_nvim_ask = true

vim.api.nvim_create_user_command("NvimAsk", function(opts)
  require("nvim-ask").open({ range = opts.range > 0 })
end, { range = true, desc = "Open nvim-ask AI assistant" })
