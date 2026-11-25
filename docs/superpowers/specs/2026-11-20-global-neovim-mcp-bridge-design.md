# Global Neovim MCP bridge for codex.nvim

**Date:** 2026-11-20
**Status:** Approved in chat

## Context

codex.nvim already exposes editor tools to its terminal UI through a private Unix socket and a per-process MCP stdio helper. The bridge currently starts only in terminal UI mode and the helper requires the socket path as an argument. A global Codex MCP server therefore cannot find the live Neovim bridge. The user's configured HTTP-to-WebSocket proxy is a separate transport and does not implement the stdio mode Codex starts.

## Goal

Make the existing codex.nvim bridge discoverable to Codex MCP stdio clients while Neovim is running, with no second tool implementation or public TCP listener.

## Design

- Keep explicit socket-path launch for codex.nvim terminal sessions.
- Publish one private manifest per live Neovim process under Neovim's cache directory. It contains the process id, active socket path, and working directory. Create the directory with mode `0700`, manifest files with mode `0600`, write atomically, and remove the manifest during bridge shutdown.
- Make the stdio helper accept either its current explicit socket argument or discover a live manifest when the argument is absent. Prefer a manifest whose working directory matches the Codex process. If multiple unmatched Neovim instances are live, return an actionable error instead of routing to an arbitrary workspace. Ignore stale or malformed manifests.
- Start the bridge whenever the App Server backend has `dynamic_tools = true`, including buffer UI. The existing default for `dynamic_tools` and `auto_start` remains enabled. `dynamic_tools = false` stops the bridge.
- Document the optional global Codex MCP entry. codex.nvim does not silently edit a user's persistent Codex configuration; this user's existing entry will be changed to launch the bundled helper directly and use the shared registry.

## Scope boundaries

The socket continues to accept only MCP `tools/list` and `tools/call`. The existing per-process terminal configuration remains in place and passes its socket explicitly. The legacy raw terminal backend remains outside this bridge.

## Acceptance criteria

- A running default App Server instance publishes a private manifest and removes it when stopped.
- A stdio helper with an explicit socket path behaves as before.
- A stdio helper without an explicit path discovers the matching live Neovim bridge, rejects ambiguous instances, and ignores stale manifests.
- Buffer UI with dynamic tools enabled starts the bridge; disabling dynamic tools stops it.
- The global Codex MCP entry launches the bundled helper in stdio mode, so Codex lists the existing tools, including `openDiff`, while Neovim is running.
- The bridge remains loopback-only and does not expose general Neovim RPC or Lua execution.
