# nix-dotfiles

Reproducible dev environment for the box: zsh + oh-my-zsh, tmux, AstroNvim,
and mise — driven by a single Home Manager flake. Targets Linux and macOS
from the same `home.nix`. Username and system arch are resolved at eval
time, so the same flake works for any user on any host.

## What's in here

```
flake.nix              # one homeConfigurations.default, eval-time $USER + system
home.nix               # imports, identity, shared sessionVariables
modules/
  zsh.nix              # programs.zsh + oh-my-zsh plugins + fzf integration
  tmux.nix             # programs.tmux + plugins (sensible/yank/resurrect/...,
                       # plus tmux-themepack and tmux-easy-motion built inline)
  neovim.nix           # nvim binary, runtime PATH, AstroNvim config symlinks,
                       # Nix-built treesitter parsers staged into &runtimepath
  mise.nix             # programs.mise + globalConfig (node 24.4.1)
  git.nix              # user.name/user.email + sane defaults
  dev-tools.nix        # rg/fd/bat/eza/lazygit/gh/gcc/python/lsp/... + direnv
nvim/                  # AstroNvim user config; init.lua + lua/...
                       # custom.lua is preserved verbatim from the live system.
```

The Nix store handles every binary. AstroNvim still owns its own plugin tree
via `lazy.nvim` — that one path stays mutable on purpose so updates don't
require a flake bump.

## What changes from the original setup

Faithful preservation:

- All oh-my-zsh plugins (`git`, `gitfast`, `dotenv`, `docker`, `docker-compose`,
  `colored-man-pages`, `mise`) and the `robbyrussell` theme.
- The cyan `[hostname]` prompt prefix.
- Every tmux keybind (prefix `C-w`, vi pane motions, `V`/`H` splits, `C-p`
  fzf-window switcher, easy-motion on `F`, etc.) and the powerline/block/cyan
  theme.
- The full AstroNvim config, including `lua/plugins/custom.lua` (leap.nvim,
  claudecode.nvim, the 6 colorschemes, the heirline statusline override, the
  tailwind+cva LSP regex tweaks).
- mise still owns `~/.config/mise/config.toml`. Project `.mise.toml` files
  keep working as before. Note: the base Node now comes from Nix
  (`nodejs_24` in `dev-tools.nix`) instead of a mise-managed global pin —
  see *Why no global Node pin in mise* below.

Improvements:

- **Tmux plugins actually load.** The original `~/.tmux.conf` referenced TPM
  and tmux-themepack but neither was installed on disk. Home Manager's
  `programs.tmux.plugins` replaces TPM entirely — plugins live in the Nix
  store, no runtime clone, and `tmux-themepack`/`tmux-easy-motion` are built
  inline since they aren't curated in nixpkgs.
- **Mason becomes optional.** `lua-language-server`, `stylua`, `prettier`,
  `typescript-language-server`, `tailwindcss-language-server`, etc. live in
  `home.packages`, so the editor never has to download a binary on first
  launch.
- **Treesitter parsers are pre-built.** Languages declared in `modules/neovim.nix`
  compile in the Nix store, then symlink into `~/.local/share/nvim/site/parser/`.
  nvim-treesitter sees them as already-installed; first-open of any covered
  filetype is instant. See the *Adding a treesitter parser* section below.
- **Secrets stop living in `.zshrc`.** Tokens move to
  `~/.config/zsh/secrets.zsh` (chmod 600, gitignored), sourced from the
  generated zshrc. The Nix store never sees them.
- **direnv + nix-direnv** are wired in for per-project envs that don't need
  to leak into the global shell.
- **Cross-platform, user-agnostic.** `aarch64-linux`, `x86_64-linux`,
  `aarch64-darwin`, `x86_64-darwin` all build from the same `home.nix`, and
  `$USER` is read at eval time so the same command works for any user.

## First-time bootstrap

### TL;DR — one command

```sh
git clone https://github.com/idpbond/nix.git nix-dotfiles && cd nix-dotfiles
./install.sh
```

`install.sh` detects Alpine / Debian / Ubuntu / Fedora / Arch / macOS,
installs the right prerequisites, runs the Determinate Nix installer with
the right flags (auto-detects systemd vs. `--init none`), reclaims `/nix`
ownership when needed, drops a secrets-file template at
`~/.config/zsh/secrets.zsh`, and runs `home-manager switch`. Idempotent —
safe to re-run.

If you'd rather do it manually (or your distro isn't recognised), follow
the steps below.

### 1. Install Nix

**Debian / Ubuntu / Fedora / macOS** — Determinate's installer detects
systemd/launchd automatically:

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

**Alpine (or any non-systemd Linux)** — pass `linux --init none` to install
in daemon-less mode. Alpine's minimal image lacks `curl`, `sudo`, and a few
others, so install those first:

```sh
sudo apk add curl sudo xz git shadow zsh gcompat
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
  sh -s -- install linux --init none
```

(`gcompat` is the glibc-shim layer that lets vendor-built binaries like
`claude-code`'s official release run on musl — Nix can't help with this
because the ELF interpreter path is baked into the binary at compile time
and points at `/lib64/`.)

`--init none` still installs `/nix` root-owned, which prevents non-root
`nix` invocations. Reclaim it for your user before continuing:

```sh
sudo chown -R "$USER:$USER" /nix
```

If you prefer the upstream installer, enable flakes manually after install
by adding `experimental-features = nix-command flakes` to
`~/.config/nix/nix.conf`.

After install, source the profile or open a fresh shell:

```sh
. /etc/profile.d/nix.sh
nix --version
```

### 2. Move existing dotfiles aside

Home Manager refuses to overwrite hand-edited files. Either remove them or
let HM do it for you with `-b backup` (it appends `.backup`):

```sh
# Manual cleanup, if you prefer
mv ~/.zshrc ~/.zshrc.pre-nix
mv ~/.tmux.conf ~/.tmux.conf.pre-nix
mv ~/.config/nvim ~/.config/nvim.pre-nix
mv ~/.config/mise ~/.config/mise.pre-nix
```

### 3. Stash secrets

```sh
mkdir -p ~/.config/zsh
cat > ~/.config/zsh/secrets.zsh <<'EOF'
export CLAUDE_CODE_OAUTH_TOKEN='...'
export BOND_BOX_AGENT_PORT='19821'
export SOPS_AGE_KEY_CMD='bond-box-agent get-key'
EOF
chmod 600 ~/.config/zsh/secrets.zsh
```

### 4. Apply the flake

One command, identical on every host and user:

```sh
cd path/to/nix-dotfiles
nix run home-manager/master -- switch --impure --flake ".#default" -b backup
```

Note the placement of `--impure`: it must go **after `switch`** so the
inner flake eval (the one that resolves `homeConfigurations.default`) gets
the flag. Putting `--impure` after `nix run` only enables impurity for
fetching home-manager itself, not for evaluating your flake — and the
attribute won't be found.

After the first switch, `home-manager` is on PATH directly:

```sh
home-manager switch --impure --flake ".#default"
```

### 5. Reload your shell

The new `~/.zshrc` is symlinked into place but the *current* shell still
has the old PATH. Open a new terminal or:

```sh
exec zsh
```

Make zsh your login shell if it isn't already:

```sh
# Linux: pick whichever zsh is on PATH first; usually the Nix one wins.
sudo chsh -s "$(command -v zsh)" "$USER"
```

On Alpine you may need to first `sudo apk add zsh` so a system zsh exists
in `/etc/shells`, or list `~/.nix-profile/bin/zsh` in `/etc/shells` by hand.

### 6. First-launch nvim

If you ran `install.sh` it already pre-warmed the plugin cache headlessly,
so opening `nvim` lands you straight in a ready editor. If you skipped that
or did the manual flow, run it once yourself:

```sh
nvim --headless '+Lazy! sync' +qa
```

LSPs, formatters, and treesitter parsers are already on PATH and in
`&runtimepath`, so Mason and TSInstall both stay idle.

## Day-to-day

| Action | Command |
| --- | --- |
| Apply config changes | `home-manager switch --impure --flake ".#default"` |
| Update all inputs | `nix flake update` then switch |
| Update one input | `nix flake lock --update-input nixpkgs` then switch |
| Roll back | `home-manager generations` then `/nix/store/.../activate` |
| Garbage-collect old generations | `nix-collect-garbage --delete-older-than 14d` |
| See what changed | `nix store diff-closures /nix/var/nix/profiles/per-user/$USER/home-manager-{N-1,N}-link` |

## Adding a tool

Add it to `modules/dev-tools.nix` and `home-manager switch`. Done.

## Adding a tmux plugin

`modules/tmux.nix → programs.tmux.plugins`. Anything in `pkgs.tmuxPlugins.*`
just works; for plugins not curated in nixpkgs (e.g. `tmux-easy-motion`,
`tmux-themepack`), copy the `mkTmuxPlugin` blocks already in that file. On
first build the inline plugin will fail with a `sha256` mismatch — Nix
prints the real hash; paste it back in.

## Adding a treesitter parser

Edit `parserLanguages` in `modules/neovim.nix` and `home-manager switch`.
The list of available identifiers:

```sh
nix eval --impure --expr 'with import <nixpkgs> {};
  builtins.attrNames vimPlugins.nvim-treesitter.builtGrammars'
```

Not every name has a standalone parser (`jsonc` is part of `json`, for
example). Eval errors will tell you what suggestions exist.

## Adding a nvim plugin

Edit `nvim/lua/plugins/custom.lua` (or add a new file under
`nvim/lua/plugins/`) and `home-manager switch` to ship the new file, then
`:Lazy sync` inside nvim. We deliberately do *not* manage lazy.nvim's plugin
set through Nix — AstroNvim is the source of truth for that tree.

## Files vs. XDG paths

Home Manager prefers XDG locations where the upstream tool supports them:

| Symlink | Target |
| --- | --- |
| `~/.zshrc` | generated zshrc |
| `~/.config/tmux/tmux.conf` | generated tmux config (tmux ≥3.1 reads this; the legacy `~/.tmux.conf` is ignored) |
| `~/.config/nvim/init.lua` | this repo's `nvim/init.lua` |
| `~/.config/nvim/lua` | this repo's `nvim/lua/` |
| `~/.local/share/nvim/site/parser` | Nix-built treesitter parsers |
| `~/.config/mise/config.toml` | `programs.mise.globalConfig` |
| `~/.config/git/config` | `programs.git.settings` |

## Portability checklist

To rebuild this environment on a fresh box you need three things:

1. Nix installed (see step 1 above).
2. The `nix-dotfiles/` directory (with `flake.lock` checked in for byte-identical builds).
3. `~/.config/zsh/secrets.zsh` with your tokens.

Then:

```sh
nix run home-manager/master -- switch --impure --flake ".#default" -b backup
```

`flake.lock` lives inside the repo and pins nixpkgs + home-manager, so any
two boxes that switch from the same lockfile end up with the same closure.

## Installing Claude Code on Alpine

Three options, in order of how-much-pain:

1. **Anthropic's signed apk repo (recommended):**

   ```sh
   sudo wget -O /etc/apk/keys/claude-code.rsa.pub \
     https://downloads.claude.ai/keys/claude-code.rsa.pub
   echo "https://downloads.claude.ai/claude-code/apk/stable" \
     | sudo tee -a /etc/apk/repositories
   sudo apk update && sudo apk add claude-code ripgrep

   mkdir -p ~/.claude && cat > ~/.claude/settings.json <<'JSON'
   { "env": { "USE_BUILTIN_RIPGREP": "0" } }
   JSON
   ```

   Native musl build, signed, auto-updates with `apk upgrade`.

2. **npm via Nix's musl-native node:**

   ```sh
   mkdir -p ~/.npm-global
   npm config set prefix ~/.npm-global
   npm install -g @anthropic-ai/claude-code
   export PATH=~/.npm-global/bin:$PATH
   ```

   Pulls the `linux-arm64-musl` artifact through npm's optional-dependency
   mechanism. Works today on Alpine because `nodejs_24` from Nix is musl.

3. **mise (currently broken on this flake's pinned mise):** the
   `aqua:anthropics/claude-code` route downloads the glibc binary and crashes
   on musl. Fixed upstream in mise ≥ 2026.4.23 (env: `MISE_LIBC=musl`) and
   fully resolved in 2026.5.2 (registry libc-variant overrides), but the Nix
   package is currently pinned at 2026.4.20. The flake already exports
   `MISE_LIBC=musl` automatically on musl hosts (see `modules/zsh.nix`), so
   the moment nixpkgs ships a fixed mise, `nix flake update && switch` makes
   `mise install claude` Just Work.

## Why no global Node pin in mise

mise downloads prebuilt Node binaries from nodejs.org that are linked
against glibc. Alpine and other musl-based distros aren't ABI-compatible,
so mise falls back to compiling Node from source — which needs the full
C/C++ toolchain (`build-base`, `python3`, `linux-headers`, ...) and ~1
hour of CPU.

Instead of pinning Node in `programs.mise.globalConfig`, the base Node
lives in `modules/dev-tools.nix` (`nodejs_24`). Nix builds the right ABI
for whichever host you're on. Project-specific Node versions still work
through a project `.mise.toml`:

```toml
[tools]
node = "20.18.0"
```

If you really need mise to compile Node from source on Alpine:

```sh
sudo apk add build-base python3 linux-headers
```

…then `mise install` in the project dir.

The same logic applies to any interpreter mise manages: prefer Nix for the
system-wide default, mise for project pins.

## Common bootstrap errors

| Symptom | Cause | Fix |
| --- | --- | --- |
| `opening lock file "/nix/var/nix/db/big-lock": Permission denied` | `/nix` is root-owned (Alpine `--init none` install) | `sudo chown -R "$USER:$USER" /nix` |
| `does not provide attribute '...homeConfigurations.default.activationPackage'` | `--impure` placed before `home-manager/master` instead of after `switch` | Move the flag: `nix run home-manager/master -- switch --impure --flake ".#default"` |
| Existing files would be clobbered | Hand-edited dotfiles in the way | Add `-b backup` (HM appends `.backup`) or move them aside manually |
| `tmux source-file: file not found` | First-time-build sha256 mismatch on an inline tmux plugin | Paste the real hash that Nix printed back into `modules/tmux.nix` |
| Determinate installer prints `WARN SelfTest([ShellFailed { ... daemon-socket/socket: No such file or directory })` | `--init none` mode doesn't start a daemon; the installer's self-test can't reach it | Benign. We chown `/nix` to your user immediately after, so single-user-style operation works regardless. |
| `Error during parser installation: EACCES ... site/parser/<lang>.so` | nvim-treesitter tried to write into the read-only Nix-managed parser dir for a missing language | Add `<lang>` to `parserLanguages` in `modules/neovim.nix` and `home-manager switch`. `auto_install` is already off so this only happens for languages we haven't pre-staged. |
| `zsh: no such file or directory: /path/to/some-vendor-binary` (file exists, is executable) | Alpine: glibc-linked binary on musl can't find its ELF interpreter | `sudo apk add gcompat` (already in `install.sh`'s Alpine prereqs for fresh installs). |
