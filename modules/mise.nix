{ ... }:

{
  programs.mise = {
    enable = true;
    enableZshIntegration = true;

    # We deliberately don't pin `node` (or any other interpreter) globally
    # here. The base interpreter comes from Nix (see dev-tools.nix), which
    # avoids glibc-vs-musl headaches on Alpine — mise's prebuilt binaries
    # are glibc-only, so a global pin here would force a source compile on
    # musl distros and need build-base + python + linux-headers + an hour
    # of CPU time. Keep mise reserved for project-scoped pins via
    # .mise.toml; native CLIs (claude, etc.) still work because they ship
    # statically.
    globalConfig = { };
  };
}
