{ config, pkgs, lib, ... }:

# Tracked secrets: secrets/env.yaml is a flat KEY: value map, encrypted with
# sops to the YubiKey PGP keys in .sops.yaml. Only ciphertext enters the repo
# and the Nix store. `nix-secrets sync` decrypts it (YubiKey required) into
# 0600 files that zsh/fish source — see modules/zsh.nix and modules/fish.nix.
#
# Activation cannot decrypt by itself: Home Manager runs it with a minimal
# PATH (home.emptyActivationPath), so the host's card-capable gpg is not
# reachable, and a PIN/touch prompt mid-switch would be fragile anyway. It
# only prints a notice when the active ciphertext differs from what was last
# synced.
let
  envFile = ../secrets/env.yaml;
  pubkeys = ../secrets/pubkeys.asc;

  nix-secrets = pkgs.writeShellApplication {
    name = "nix-secrets";
    # No gnupg here on purpose: the host gpg (or $SOPS_GPG_EXEC) talks to the
    # YubiKey's gpg-agent/scdaemon; a second Nix gpg stack would not.
    runtimeInputs = with pkgs; [ sops jq yq-go coreutils gnugrep git ];
    runtimeEnv = {
      NIX_SECRETS_ACTIVATED_FILE = "${envFile}";
      NIX_SECRETS_PUBKEYS = "${pubkeys}";
    };
    text = builtins.readFile ./nix-secrets.sh;
  };
in
{
  home.packages = [ nix-secrets ];

  home.activation.nixSecretsNotice = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _stamp="${config.xdg.stateHome}/nix-dotfiles/secrets.synced"
    _want=$(sha256sum ${envFile} | cut -d' ' -f1)
    _have=""
    [ -r "$_stamp" ] && _have=$(< "$_stamp")
    if [ "$_want" != "$_have" ]; then
      warnEcho "Tracked secrets changed. Decrypt them into your shell env with:"
      warnEcho "    nix-secrets sync     (or 'nix-secrets skip' on hosts without a YubiKey)"
    fi
    unset _stamp _want _have
  '';
}
