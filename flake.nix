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
        in
        {
          package = pkg;

          selfcheck-mock = pkgs.runCommand "taskman-selfcheck-mock" { } ''
            export TASKMAN_CONFIG_DIR="$TMPDIR/config"
            export TASKMAN_DATA_DIR="$TMPDIR/data"
            mkdir -p "$TASKMAN_CONFIG_DIR" "$TASKMAN_DATA_DIR"
            ${pkgs.lib.getExe pkg} --selfcheck --mock > "$out"
          '';
        }
      );
    };
}
