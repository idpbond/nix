# Repository guidance

This repository defines a portable Home Manager environment for macOS and
Linux. Preserve cross-platform behavior and the declarative Home Manager
model when making changes. Read `README.md` for the user-facing setup and
operational details before changing bootstrap or activation behavior.

## Architecture

- `flake.nix` selects `builtins.currentSystem`, `$USER`, and `$HOME` at
  evaluation time and exposes `homeConfigurations.default`. This is
  intentionally impure; commands that evaluate the configuration need
  `--impure`.
- `home.nix` is the composition root. Program-specific Home Manager settings
  belong in `modules/*.nix`; add new modules to its imports.
- `modules/dev-tools.nix` is the shared package/tool inventory. Prefer Nix for
  global runtimes and tools; reserve mise for project-specific version pins.
- `nvim/`, `yazi/`, `alacritty/`, and `zsh/custom/` contain configuration or
  vendored assets linked or referenced by Home Manager. AstroNvim continues
  to manage its mutable plugin tree through `lazy.nvim`; do not migrate that
  tree into Nix without an explicit request.
- `install.sh` supports both personal installs and dedicated users on shared
  Linux/systemd machines. `uninstall.sh` is intentionally destructive and
  interactive by default. Keep their documented behavior and portability in
  sync with `README.md`.
- `flake.lock` is committed reproducibility state. Change it only when an
  input update is intended.

## Working conventions

- Follow the existing Nix style: two-space indentation, small program-focused
  modules, and comments for non-obvious platform or Home Manager constraints.
- Use `lib.optionals`/`lib.optionalString` and `pkgs.stdenv` checks for
  platform-specific behavior rather than duplicating the configuration.
- Prefer Home Manager options over generated ad-hoc dotfiles. When upstream
  configuration cannot be expressed faithfully, use `xdg.configFile` as the
  existing modules do.
- Keep secrets out of Nix expressions and the Nix store. Machine-local tokens
  belong in `~/.config/zsh/secrets.zsh` (or the fish equivalent), never in the
  repository.
- Preserve vendored Yazi plugin/flavor contents unless the task is explicitly
  updating that vendor snapshot.
- If behavior, commands, supported platforms, or paths change, update
  `README.md` in the same change.

## Validation

Run the narrowest relevant checks while developing, then the flake checks for
changes affecting the configuration:

```sh
./modules/tmux-navigate.test.sh
./modules/tmux-layout-glyph.test.sh
nix flake check --impure
```

For shell changes, also run `shellcheck` on the touched scripts. For Lua
changes under `nvim/`, use the repository's StyLua and Selene configuration
where applicable. A full activation mutates the user's live environment, so
do not run it merely as a test unless the user asks:

```sh
home-manager switch --impure --flake ".#default"
```

When changing tmux navigation or layout classification, add or update fixed
fixtures in the adjacent `*.test.sh` file. Avoid tests that require a live
tmux server or timing.

## Important invariants

- The same flake must continue to evaluate on `aarch64-linux`, `x86_64-linux`,
  `aarch64-darwin`, and `x86_64-darwin` unless scope is explicitly narrowed.
- Keep `flake.lock` tracked and use the `default` Home Manager configuration.
- Do not put secrets into the Nix store.
- Do not replace Nix-built Treesitter parsers or PATH-provided LSP/formatter
  tools with first-launch downloads. Add parsers in `modules/neovim.nix` and
  general tools in `modules/dev-tools.nix`.
- Inline tmux plugins require pinned revisions and real fixed-output hashes.
- Preserve user-authored work in a dirty worktree and avoid activating or
  uninstalling the live Home Manager profile as an incidental verification
  step.
