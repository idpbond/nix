{ pkgs, lib, ... }:

{
  # IosevkaTerm Nerd Font for terminals + GUI apps. Imported conditionally
  # from home.nix only when `withGui = true` (auto on macOS, WITH_GUI=1 on
  # Linux) — saves ~150MB of font files on headless boxes that wouldn't
  # render them anyway.
  home.packages = with pkgs; [
    nerd-fonts.iosevka-term
  ];

  # Tell fontconfig about HM-managed fonts. No-op on macOS (which uses
  # CoreText); essential on Linux so apps find the new font without a
  # `fc-cache -fv` reboot.
  fonts.fontconfig.enable = lib.mkDefault pkgs.stdenv.isLinux;
}
