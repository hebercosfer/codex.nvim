# Makefile for codex.nvim testing and coverage
# Usage:
#   make test                      - unit specs (tests/specs)
#   make test-codex CODEX_BIN=...  - contract spec against a real codex app-server
#   make coverage                  - unit specs + coverage, gated on the baseline
#   make coverage-update           - raise tests/coverage-baseline.txt after coverage went up

# plenary.nvim drives the specs. Point PLENARY_DIR at a checkout, or install it
# under ~/.local/share/nvim/site/pack/test/start.
PLENARY_DIR ?= $(firstword $(wildcard \
	$(HOME)/.local/share/nvim/site/pack/test/start/plenary.nvim \
	$(HOME)/.local/share/nvim/lazy/plenary.nvim \
	.tests/plenary.nvim))

# Real Codex CLI for the contract spec. Defaults to whatever `codex` is on PATH.
CODEX_BIN ?= codex

.PHONY: test test-codex coverage coverage-update clean install-deps

# Unit specs only: they stub termopen and never start a Codex or Claude process.
# tests/bin holds a stand-in `codex`, so a missing CLI on the machine never starts an install prompt.
test:
	@bash -c 'mkdir -p /tmp/codex-nvim-empty-config && \
	  if command -v luarocks >/dev/null 2>&1; then eval "$$(luarocks --lua-version=5.1 path)"; fi && \
	  PATH="$(CURDIR)/tests/bin:$$PATH" PLENARY_DIR=$(PLENARY_DIR) XDG_CONFIG_HOME=/tmp/codex-nvim-empty-config \
	  nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/specs/ { minimal_init = '\''tests/minimal_init.lua'\'', sequential = true }"'

# Contract spec against a real `codex app-server`: CLI flags and the initialize handshake.
test-codex:
	PLENARY_DIR=$(PLENARY_DIR) CODEX_BIN=$(CODEX_BIN) \
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/integration/codex_cli_spec.lua"

# Line coverage of lua/codex, as a ratchet: `make coverage` fails when the total drops
# below tests/coverage-baseline.txt, and `make coverage-update` raises the baseline when
# coverage has gone up. Every spec runs in its own child Neovim, so the recording starts
# in each child (CODEX_LUACOV, see tests/minimal_init.lua).
COVERAGE_BASELINE := tests/coverage-baseline.txt

coverage:
	@bash -c 'mkdir -p /tmp/codex-nvim-empty-config && \
	  if command -v luarocks >/dev/null 2>&1; then eval "$$(luarocks --lua-version=5.1 path)"; fi && \
	  rm -f luacov.stats.out luacov.report.out lcov.info && \
	  PATH="$(CURDIR)/tests/bin:$$PATH" CODEX_LUACOV=1 PLENARY_DIR=$(PLENARY_DIR) XDG_CONFIG_HOME=/tmp/codex-nvim-empty-config \
	  nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/specs/ { minimal_init = '\''tests/minimal_init.lua'\'', sequential = true }" && \
	  luacov && \
	  total=$$(awk '\''/^Total/ {gsub("%", "", $$NF); print $$NF}'\'' luacov.report.out) && \
	  base=$$(cat $(COVERAGE_BASELINE)) && \
	  echo "Line coverage: $$total% (baseline $$base%)" && \
	  awk -v t="$$total" -v b="$$base" '\''BEGIN { exit (t + 0 < b + 0) }'\'' || { echo "coverage fell below the baseline; add tests, or fix the regression" >&2; exit 1; } && \
	  luacov -t LcovReporter > lcov.info'

# Run after `make coverage`: raises the baseline to the measured total, never lowers it.
coverage-update:
	@bash -c 'test -f luacov.report.out || { echo "run make coverage first" >&2; exit 1; } && \
	  total=$$(awk '\''/^Total/ {gsub("%", "", $$NF); print $$NF}'\'' luacov.report.out) && \
	  base=$$(cat $(COVERAGE_BASELINE)) && \
	  awk -v t="$$total" -v b="$$base" '\''BEGIN { exit !(t + 0 > b + 0) }'\'' && \
	  echo "$$total" > $(COVERAGE_BASELINE) && echo "baseline raised: $$base% -> $$total%" || echo "baseline stays at $$base% (measured $$total%)"'

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
