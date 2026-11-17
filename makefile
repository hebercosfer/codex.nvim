# Makefile for codex.nvim testing and coverage
# Usage:
#   make test                      - unit specs (tests/specs)
#   make test-codex CODEX_BIN=...  - contract spec against a real codex app-server
#   make coverage                  - unit specs + coverage (luacov + lcov.info)

# plenary.nvim drives the specs. Point PLENARY_DIR at a checkout, or install it
# under ~/.local/share/nvim/site/pack/test/start.
PLENARY_DIR ?= $(firstword $(wildcard \
	$(HOME)/.local/share/nvim/site/pack/test/start/plenary.nvim \
	$(HOME)/.local/share/nvim/lazy/plenary.nvim \
	.tests/plenary.nvim))

# Real Codex CLI for the contract spec. Defaults to whatever `codex` is on PATH.
CODEX_BIN ?= codex

.PHONY: test test-codex coverage clean install-deps

# Unit specs only: they stub termopen and never start a Codex or Claude process.
test:
	@bash -c 'mkdir -p /tmp/codex-nvim-empty-config && \
	  if command -v luarocks >/dev/null 2>&1; then eval "$$(luarocks --lua-version=5.1 path)"; fi && \
	  PLENARY_DIR=$(PLENARY_DIR) XDG_CONFIG_HOME=/tmp/codex-nvim-empty-config \
	  nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/specs/ { minimal_init = '\''tests/minimal_init.lua'\'', sequential = true }"'

# Contract spec against a real `codex app-server`: CLI flags and the initialize handshake.
test-codex:
	PLENARY_DIR=$(PLENARY_DIR) CODEX_BIN=$(CODEX_BIN) \
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/integration/codex_cli_spec.lua"

coverage:
	@bash -c 'mkdir -p /tmp/codex-nvim-empty-config && \
	  if command -v luarocks >/dev/null 2>&1; then eval "$$(luarocks --lua-version=5.1 path --bin)"; fi && \
	  XDG_CONFIG_HOME=/tmp/codex-nvim-empty-config nvim --headless -u tests/minimal_init.lua -c "luafile tests/run_cov.lua" || exit 0 && \
	  if [ -f luacov.stats.out ]; then \
	    echo "::group::Coverage"; \
	    luacov -t LcovReporter > lcov.info; \
	    echo "::endgroup::"; \
	  else \
	    echo "luacov.stats.out not found, skipping coverage report."; \
	  fi'

clean:
	rm -f luacov.stats.out lcov.info
	@echo "Cleaned coverage artifacts"

install-deps:
	luarocks --lua-version=5.1 install --local luacov
	luarocks --lua-version=5.1 install --local luacov-reporter-lcov
	luarocks --lua-version=5.1 install --local luacheck
	if [ ! -d ~/.local/share/nvim/site/pack/test/start/plenary.nvim ]; then \
		echo "Installing plenary.nvim dependency..."; \
		mkdir -p ~/.local/share/nvim/site/pack/test/start; \
		git clone https://github.com/nvim-lua/plenary.nvim ~/.local/share/nvim/site/pack/test/start/plenary.nvim || true; \
	else \
		echo "plenary.nvim already installed."; \
	fi
