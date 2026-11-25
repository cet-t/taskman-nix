{
  description = "TaskMan for NixOS — a fast Rust task manager and system monitor (MIT fork of aufkrawall/taskman)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      mkPackage = pkgs: pkgs.callPackage ./nix/package.nix { };
      defaultPackageFor = pkgs: self.packages.${pkgs.stdenv.hostPlatform.system}.taskman;
    in
    {
      packages = forAllSystems (pkgs: {
        taskman = mkPackage pkgs;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.taskman;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = nixpkgs.lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.taskman;
          meta = self.packages.${pkgs.stdenv.hostPlatform.system}.taskman.meta;
        };
      });

      overlays.default = final: _prev: {
        taskman = mkPackage final;
      };

      nixosModules = {
        taskman = import ./nix/nixos-module.nix defaultPackageFor;
        default = self.nixosModules.taskman;
      };

      homeManagerModules = {
        taskman = import ./nix/home-manager-module.nix defaultPackageFor;
        default = self.homeManagerModules.taskman;
      };

      devShells = forAllSystems (
        pkgs:
        let
          runtimeLibs = [
            pkgs.wayland
            pkgs.libxkbcommon
            pkgs.libglvnd
            pkgs.vulkan-loader
            pkgs.libx11
            pkgs.libxcursor
            pkgs.libxi
            pkgs.libxrandr
            pkgs.libxcb
          ];
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.rustc
              pkgs.cargo
              pkgs.clippy
              pkgs.rustfmt
              pkgs.pkg-config
              pkgs.python3
              pkgs.fontconfig
              pkgs.xdg-utils
            ];

            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath runtimeLibs;
          };
        }
      );

      checks = forAllSystems (
        pkgs:
        let
          pkg = self.packages.${pkgs.stdenv.hostPlatform.system}.taskman;
          nixosEval = nixpkgs.lib.nixosSystem {
            system = pkgs.stdenv.hostPlatform.system;
            modules = [
              self.nixosModules.default
              {
                programs.taskman.enable = true;
                system.stateVersion = "25.05";
                fileSystems."/" = {
                  device = "nodev";
                  fsType = "ext4";
                };
                boot.loader.grub.device = "nodev";
              }
            ];
          };
        in
        {
          package = pkg;

          selfcheck-mock = pkgs.runCommand "taskman-selfcheck-mock" { } ''
            export TASKMAN_CONFIG_DIR="$TMPDIR/config"
            export TASKMAN_DATA_DIR="$TMPDIR/data"
            mkdir -p "$TASKMAN_CONFIG_DIR" "$TASKMAN_DATA_DIR"
            ${pkgs.lib.getExe pkg} --selfcheck --mock > "$out"
          '';

          privileged-helper-contract = pkgs.runCommand "taskman-privileged-helper-contract" { } ''
            helper="${pkg}/libexec/taskman-privileged-helper"
            policy="${pkg}/share/polkit-1/actions/io.github.cet_t.Taskman.policy"

            test -x "$helper"
            test ! -e "${pkg}/bin/taskman-privileged-helper"

            # Verify helper is a direct ELF binary, never a shell wrapper script.
            magic="$(od -An -tx1 -N4 "$helper" | tr -d ' \n')"
            test "$magic" = "7f454c46"

            # Missing args must fail with exit code 2.
            set +e
            "$helper"
            rc_missing=$?
            "$helper" --linux-privileged-action=kill --linux-privileged-pid=999999 --linux-privileged-identity=1
            rc_nonroot=$?
            set -e
            test "$rc_missing" -eq 2
            test "$rc_nonroot" -eq 1

            # Verify Polkit policy binds the exact immutable helper store path and disables GUI forwarding.
            test -f "$policy"
            grep -Fq "<annotate key=\"org.freedesktop.policykit.exec.path\">$helper</annotate>" "$policy"
            grep -Fq '<annotate key="org.freedesktop.policykit.exec.allow_gui">false</annotate>' "$policy"

            echo "ok" > "$out"
          '';

          nixos-module = pkgs.runCommand "taskman-nixos-module-check" { } ''
            test "${nixpkgs.lib.boolToString nixosEval.config.security.polkit.enable}" = "true"
            test "${nixpkgs.lib.boolToString (builtins.elem "/share/polkit-1" nixosEval.config.environment.pathsToLink)}" = "true"
            test "${nixpkgs.lib.boolToString (builtins.any (p: (p.pname or "") == "taskman") nixosEval.config.environment.systemPackages)}" = "true"
            echo "ok" > "$out"
          '';
        }
      );
    };
}
