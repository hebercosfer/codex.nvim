# Neovim MCP Bridge for codex.nvim

**Date:** 2026-11-11  
**Status:** Design approved in chat; implementation pending

## Context

codex.nvim already registers Neovim editor tools, including `openDiff`. In App Server buffer mode, the plugin starts the thread and supplies those tools through `thread/start.dynamicTools`. In terminal mode, the remote Codex TUI starts its own thread, so it does not receive the plugin's dynamic tool definitions. The handlers exist, but that terminal session cannot call them through the current handoff.

## Goal

Expose codex.nvim's existing Neovim tools to the remote Codex TUI through MCP, without changing a user's persistent Codex configuration or edit-approval policy.

## Design

- Add a small MCP stdio helper, launched by the remote Codex TUI for the session.
- Have the plugin own a private local socket between Neovim and the helper. The socket protocol supports only listing and calling registered codex.nvim tools; it does not expose general Neovim RPC or arbitrary Lua execution.
- Inject the helper command and arguments with per-process Codex `--config mcp_servers.codex_nvim.*` overrides when codex.nvim opens a remote TUI. Do not write to `~/.codex/config.toml` or project Codex configuration.
- Reuse the current tool registry and handlers. Convert their schemas and results to MCP's `tools/list` and `tools/call` formats. Keep deferred handlers, especially `openDiff`, pending until their callback reports the user's accept/reject decision.
- Use `app_server.dynamic_tools` as the gate for terminal-mode MCP exposure. Leave App Server buffer mode's dynamic-tool path and the legacy raw terminal backend unchanged.
- Start and stop the private listener with the App Server plugin lifecycle. If it cannot start, log a clear warning and allow the Codex TUI to open without Neovim tools. Return handler failures as MCP tool errors.

## Scope boundaries

This change makes Neovim tools available to terminal-mode Codex; it does not force Codex to choose `openDiff` instead of its built-in editing capabilities. The user's personal Codex sandbox and approval settings remain under the user's control. No changes are made to the dotfiles checkout or to external Neovim MCP providers.

## Acceptance criteria

- With App Server terminal mode and `dynamic_tools = true`, the launched Codex TUI has an MCP server backed by the active Neovim instance.
- MCP tool listing exposes the existing codex.nvim tools and their input schemas.
- MCP tool calls reach the corresponding existing handlers, including deferred calls that complete after Neovim UI interaction.
- With `dynamic_tools = false`, buffer UI, or the legacy raw terminal backend, this bridge is not injected.
- Codex's persistent configuration and sandbox policy are not modified.
