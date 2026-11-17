-- What codex.nvim is verified against. The pinned grid in .github/workflows/compat.yml
-- runs every entry, and the scheduled drift check compares the newest codex_cli entry
-- with what npm ships. Move these together, at release prep, with the grid green.
return {
  neovim = { 'v0.10.4', 'v0.11.5', 'stable' },
  codex_cli = { '0.161.0', '0.166.0', '0.169.0' },
}
