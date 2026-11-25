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

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to install a declarative XDG autostart desktop entry for TaskMan.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."autostart/io.github.cet_t.Taskman.desktop" = lib.mkIf cfg.autostart {
      text = ''
        [Desktop Entry]
        Type=Application
        Version=1.0
        Name=Taskman
        Comment=Cross-platform task manager and system monitor
        Exec=${lib.getExe cfg.package}
        Icon=utilities-system-monitor
        Terminal=false
        Categories=System;Monitor;
        Keywords=task;manager;process;system;monitor;
        StartupNotify=false
        Hidden=false
        X-GNOME-Autostart-enabled=true
      '';
    };
  };
}
