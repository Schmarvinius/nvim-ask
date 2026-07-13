-- Minimal init for running the test suite headlessly.
--
--   nvim --headless --clean -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/spec/ { minimal_init = 'tests/minimal_init.lua' }"
--
-- or simply `make test`.

local cwd = vim.fn.getcwd()
vim.opt.runtimepath:append(cwd)

--- Locate plenary.nvim from an env var or common install locations.
local function find_plenary()
  local candidates = {}
  if vim.env.PLENARY_DIR and vim.env.PLENARY_DIR ~= "" then
    table.insert(candidates, vim.env.PLENARY_DIR)
  end
  table.insert(candidates, cwd .. "/.tests/plenary.nvim")
  local data = vim.fn.stdpath("data")
  table.insert(candidates, data .. "/lazy/plenary.nvim")
  table.insert(candidates, data .. "/site/pack/vendor/start/plenary.nvim")
  table.insert(candidates, data .. "/site/pack/packer/start/plenary.nvim")
  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir) == 1 then
      return dir
    end
  end
  return nil
end

local plenary = find_plenary()
if not plenary then
  io.stderr:write(
    "plenary.nvim not found. Set PLENARY_DIR, or run `make test` to fetch it into .tests/.\n"
  )
  vim.cmd("cquit 1")
  return
end

vim.opt.runtimepath:append(plenary)
-- Explicitly source plenary's plugin so PlenaryBustedDirectory is defined even
-- under --clean / --noplugin.
vim.cmd("runtime plugin/plenary.vim")
