# Terminal Neovim MCP Bridge Implementation Plan

> **For agentic workers:** Execute this plan inline in the current session. Preserve the user's separate dotfiles checkout.

**Goal:** Make codex.nvim's existing Neovim tools available to the remote Codex TUI through a plugin-owned MCP stdio bridge, and close/refresh the `openDiff` review UI after a decision.

**Architecture:** The live Neovim plugin owns a private local socket that accepts only tool-list and tool-call messages. A bundled clean-Neovim helper speaks MCP over stdio and forwards calls across that socket. codex.nvim adds per-process `--config` overrides to the remote TUI command; the persistent Codex configuration remains untouched.

**Tech Stack:** LuaJIT, Neovim libuv and JSON APIs, Codex CLI MCP stdio configuration.

**Spec:** `docs/superpowers/specs/2026-11-11-neovim-mcp-bridge-design.md`

## Global Constraints

- Gate the bridge on `backend = 'app_server'`, `app_server.ui = 'terminal'`, and `app_server.dynamic_tools = true`.
- Leave the user's persistent Codex configuration, sandbox, and approval policy unchanged.
- Preserve the existing buffer UI dynamic-tool path and legacy raw terminal backend.
- Keep the socket protocol restricted to tool listing and tool calls; do not expose arbitrary Neovim RPC or Lua execution.
- Preserve current uncommitted work in the separate dotfiles checkout.

---

### Task 1: Add MCP tool adaptation and the local bridge

**Files:**
- Create: `lua/codex/mcp_bridge.lua`
- Create: `lua/codex/mcp_stdio.lua`
- Modify: `lua/codex/tools/init.lua`

**Interfaces:**
- `tools.get_mcp_specs()` returns sorted MCP tool records with `name`, `description`, and `inputSchema`, omitting the App Server-only `namespace` field.
- `tools.handle_mcp(params, respond)` dispatches `params.name` and `params.arguments`; it responds with MCP `content` and `isError`, including after a deferred handler callback.
- `mcp_bridge.start(dispatch)` returns `socket_path, nil` on success or `nil, error` on failure. `mcp_bridge.stop()` closes clients, listener, and socket path.
- The helper handles MCP `initialize`, `notifications/initialized`, `ping`, `tools/list`, and `tools/call` over line-delimited stdio JSON. Its local socket requests are limited to `tools/list` and `tools/call`.

- [ ] Implement the MCP adapter over the existing tool registry. Convert returned values to JSON text content; mark unknown tools and thrown handler errors as MCP errors; retain the existing deferred-callback behavior.
- [ ] Implement a private libuv local-socket listener. Decode each newline-delimited request, dispatch only the two supported methods, return correlated JSON responses, and close all handles on stop.
- [ ] Implement the standalone helper using the current Neovim executable. Keep protocol output on stdout and diagnostics on stderr. Forward list and call requests to the plugin listener and return MCP JSON-RPC responses.

### Task 2: Wire the bridge into terminal launches

**Files:**
- Modify: `lua/codex/app_server.lua`
- Modify: `lua/codex/terminal.lua`
- Modify: `README.md`

- [ ] Start the listener only for App Server terminal mode with dynamic tools enabled, before launching a remote TUI; log a warning but allow the TUI to open if listener startup fails.
- [ ] Stop the listener with the existing App Server shutdown lifecycle.
- [ ] Carry the helper path and socket path with each remote session and append `--config` overrides for `mcp_servers.codex_nvim.command`, `args`, and `enabled`. Encode values as TOML-safe strings/arrays; do not edit user config files.
- [ ] Do not inject the MCP server into buffer UI or legacy terminal commands.
- [ ] Document terminal-mode tool availability, the `dynamic_tools` gate, and that the bridge does not change Codex's direct-edit permissions.

### Task 3: Finish `openDiff` after accept or reject

**Files:**
- Modify: `lua/codex/tools/open_diff.lua`

- [ ] Capture the original and proposal buffers/windows before opening the review.
- [ ] On either accept or reject, turn diff mode off in the captured windows, close the proposal split, and delete its temporary buffer/file.
- [ ] On accept, check the destination write result, refresh an already-open destination buffer with the accepted contents, and leave the destination available in the editor. Return a tool error if saving fails.
- [ ] On reject or cancellation, preserve the original file and return a rejected result.
- [ ] Complete the deferred MCP response only after the cleanup and final accept/reject result.

### Task 4: Review and commit

- [ ] Inspect the complete diff for scope, socket cleanup, terminal argument quoting, and preservation of the existing handlers.
- [ ] Run `git diff --check` and confirm the dotfiles checkout remains untouched.
- [ ] Create a local feature commit; do not push or open a PR.
