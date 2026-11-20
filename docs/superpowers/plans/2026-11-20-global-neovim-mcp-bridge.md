# Global Neovim MCP Bridge Implementation Plan

> **For agentic workers:** Execute this plan inline in the current session. Preserve unrelated user configuration and workspace edits.

**Goal:** Let a Codex MCP stdio process find and call the tools exposed by a live codex.nvim instance.

**Architecture:** codex.nvim publishes a private per-process manifest for its existing local socket. The bundled MCP stdio helper resolves that manifest when no explicit socket is provided; terminal sessions continue to receive the explicit socket through their temporary Codex config.

**Tech Stack:** LuaJIT, Neovim libuv/JSON APIs, Codex MCP stdio configuration.

**Spec:** `docs/superpowers/specs/2026-11-20-global-neovim-mcp-bridge-design.md`

## Global Constraints

- Keep the bridge limited to `tools/list` and `tools/call`.
- Store manifests under Neovim's cache directory with directory mode `0700` and file mode `0600`.
- Keep `dynamic_tools = true` as the default and honor `dynamic_tools = false` as the bridge shutdown gate.
- Preserve explicit socket arguments for terminal sessions launched by codex.nvim.
- Do not make the plugin silently edit persistent Codex configuration.

---

### Task 1: Add a private live-bridge registry

**Files:**
- Create: `lua/codex/mcp_registry.lua`
- Create: `tests/specs/mcp_registry_spec.lua`

**Interfaces:**
- `mcp_registry.publish(socket_path, cwd)` returns `manifest_path, nil` or `nil, error`.
- `mcp_registry.find(cwd)` returns `{ socket_path, pid, cwd }` or `nil, error`.
- `mcp_registry.remove(manifest_path)` removes only the requested manifest.

- [ ] Add a test that publishes the current Neovim pid and socket path under a temporary cache directory, then finds the same record for the matching cwd.
- [ ] Run `make test` and confirm the new test fails because `codex.mcp_registry` does not exist.
- [ ] Implement private directory creation, atomic JSON manifest writes, process liveness checks, cwd preference, stale-manifest filtering, ambiguity errors, and targeted removal.
- [ ] Run `make test` and confirm the registry test and the existing suite pass.

### Task 2: Publish and remove bridge manifests

**Files:**
- Modify: `lua/codex/mcp_bridge.lua`
- Modify: `tests/specs/mcp_registry_spec.lua`

- [ ] Add a test that starts the bridge and confirms its registry entry is removed by `mcp_bridge.stop()`.
- [ ] Run the focused spec and confirm it fails because bridge startup does not publish a manifest.
- [ ] Publish after the local socket starts listening, retain the manifest path, and remove it with the socket during shutdown.
- [ ] Keep the local socket usable if registry publication fails; log a warning for discovery clients.
- [ ] Run the focused spec and confirm publish/cleanup behavior passes.

### Task 3: Add helper-side discovery and start the bridge in default App Server modes

**Files:**
- Modify: `lua/codex/mcp_stdio.lua`
- Modify: `lua/codex/app_server.lua`
- Modify: `tests/specs/app_server_spec.lua`
- Modify: `tests/specs/mcp_registry_spec.lua`

- [ ] Add tests for resolving an explicit socket path first, discovering a matching manifest when no path is supplied, and returning the ambiguity error for multiple live unmatched instances.
- [ ] Add an App Server test that enables dynamic tools in buffer UI and asserts the Neovim bridge starts.
- [ ] Run the focused specs and confirm the discovery and buffer-UI cases fail before implementation.
- [ ] Parse socket arguments from `vim.v.argv` without treating the script filename as a socket. When absent, add the plugin Lua directory to runtimepath and call `mcp_registry.find(vim.fn.getcwd())`.
- [ ] Start the bridge whenever dynamic tools are enabled, regardless of App Server UI; retain the existing explicit helper config for terminal sessions.
- [ ] Run the focused specs and confirm discovery and lifecycle behavior pass.

### Task 4: Document and wire the user's global Codex MCP entry

**Files:**
- Modify: `README.md`
- Modify: `/home/cfs/.codex/config.toml` (user configuration, outside this repository)

- [ ] Document the optional `mcp_servers.codex_nvim` stdio entry and explain that it discovers an active Neovim bridge; keep the no-persistent-config-mutation behavior for plugin startup.
- [ ] Replace the user's `mcp_servers.neovim` Node HTTP proxy entry with `mcp_servers.codex_nvim` invoking Neovim headless with `lua/codex/mcp_stdio.lua` and no socket argument.
- [ ] Verify `git diff --check`, run `make test`, and check the configured command and argument paths without displaying unrelated config values.
