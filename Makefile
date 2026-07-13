# Run the test suite headlessly with plenary.nvim.
#
#   make test        # discover plenary (PLENARY_DIR, .tests/, or an installed copy)
#   make deps        # clone plenary into .tests/ (for CI or a clean machine)
#   make clean       # remove .tests/

PLENARY_DIR ?= .tests/plenary.nvim
NVIM ?= nvim

.PHONY: test deps clean

test:
	@if [ -z "$$(command -v $(NVIM))" ]; then echo "nvim not found"; exit 1; fi
	@$(NVIM) --headless --clean -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/spec/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"

deps: $(PLENARY_DIR)

$(PLENARY_DIR):
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR)

clean:
	rm -rf .tests
