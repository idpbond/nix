{ ... }:

# Alacritty config, tracked so it travels to every host (you use Alacritty
# everywhere). Config-ONLY: we don't install the terminal via Nix — you already
# have it — we just manage ~/.config/alacritty/alacritty.toml as a symlink, the
# same way nvim/yazi configs are handled. The notable change over the old local
# file is `window.option_as_alt = "Both"` (in alacritty/alacritty.toml), which
# makes macOS's Option key act as Alt/Meta. `option_as_alt` is macOS-only and
# ignored on Linux, so the one tracked file is correct on every host.
{
  xdg.configFile."alacritty/alacritty.toml".source = ../alacritty/alacritty.toml;
}
