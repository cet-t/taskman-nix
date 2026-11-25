defaultPackage:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.taskman;
in
{
  options.programs.taskman = {
    enable = lib.mkEnableOption "TaskMan system monitor";

    enablePrivilegedHelper = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to install the minimal GUI-free `taskman-privileged-helper` binary
        and its Polkit action policy (`io.github.cet_t.Taskman.policy`) for on-demand
        privileged process control (terminating/suspending other users' processes and
        raising nice priority or affinity).
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = (defaultPackage pkgs).override {
        withPrivilegedHelper = cfg.enablePrivilegedHelper;
      };
      defaultText = lib.literalExpression "pkgs.taskman";
      description = "The TaskMan package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Polkit is used on demand for systemd service control via `/run/wrappers/bin/pkexec`
    # and, when enabled, for `taskman-privileged-helper`.
    security.polkit.enable = lib.mkDefault true;

    # Ensure Polkit action policies installed by the package are linked into the system profile.
    environment.pathsToLink = lib.mkIf cfg.enablePrivilegedHelper [ "/share/polkit-1" ];
  };
}
