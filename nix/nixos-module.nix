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

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage pkgs;
      defaultText = lib.literalExpression "pkgs.taskman";
      description = "The TaskMan package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Polkit is used on demand for systemd service control via `/run/wrappers/bin/pkexec`.
    security.polkit.enable = lib.mkDefault true;
  };
}
