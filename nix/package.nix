{
  lib,
  rustPlatform,
  pkg-config,
  makeWrapper,
  fontconfig,
  systemd,
  xdg-utils,
  wayland,
  libxkbcommon,
  libglvnd,
  vulkan-loader,
  libx11,
  libxcursor,
  libxi,
  libxrandr,
  libxcb,
  withPrivilegedHelper ? true,
}:

let
  cargoToml = lib.importTOML ../Cargo.toml;

  runtimeLibs = [
    wayland
    libxkbcommon
    libglvnd
    vulkan-loader
    libx11
    libxcursor
    libxi
    libxrandr
    libxcb
  ];
in
rustPlatform.buildRustPackage (
  finalAttrs:
  {
    pname = "taskman";
    version = cargoToml.workspace.package.version;

    src = lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions [
        ../Cargo.toml
        ../Cargo.lock
        ../crates
        ../vendor
        ../packaging
      ];
    };

    cargoLock = {
      lockFile = ../Cargo.lock;
    };

    nativeBuildInputs = [
      pkg-config
      makeWrapper
    ];

    # Pin immutable store paths for non-setuid utilities so TaskMan works even on
    # minimal NixOS setups where fontconfig is not installed in the system profile.
    # pkexec is deliberately NOT pinned here: it must resolve to NixOS's setuid
    # wrapper at `/run/wrappers/bin/pkexec`.
    TASKMAN_FC_MATCH_PATH = "${fontconfig.bin}/bin/fc-match";
    TASKMAN_SYSTEMCTL_PATH = "${systemd}/bin/systemctl";
    TASKMAN_LOGINCTL_PATH = "${systemd}/bin/loginctl";

    cargoBuildFlags = [
      "-p"
      "tm-app"
      "--bin"
      "taskman"
    ]
    ++ lib.optionals withPrivilegedHelper [
      "-p"
      "tm-platform"
      "--bin"
      "taskman-privileged-helper"
    ];

    cargoTestFlags = [
      "-p"
      "tm-core"
      "-p"
      "tm-platform"
      "-p"
      "tm-ui"
      "-p"
      "tm-app"
    ];

    postInstall = ''
      install -Dm644 packaging/linux/io.github.cet_t.Taskman.desktop \
        "$out/share/applications/io.github.cet_t.Taskman.desktop"

      wrapProgram "$out/bin/taskman" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}" \
        --suffix PATH : "${lib.makeBinPath [ xdg-utils ]}"
    ''
    + lib.optionalString withPrivilegedHelper ''
      # Keep the privileged helper out of PATH and completely unwrapped (plain ELF)
      # so pkexec executes an immutable, root-owned, GUI-free binary directly.
      install -Dm755 "$out/bin/taskman-privileged-helper" \
        "$out/libexec/taskman-privileged-helper"
      rm -f "$out/bin/taskman-privileged-helper"

      mkdir -p "$out/share/polkit-1/actions"
      substitute packaging/linux/io.github.cet_t.Taskman.policy.in \
        "$out/share/polkit-1/actions/io.github.cet_t.Taskman.policy" \
        --replace-fail "@helperPath@" "$out/libexec/taskman-privileged-helper"
    '';

    meta = {
      description = "Task Manager and system monitor for NixOS / Linux (fork of aufkrawall/taskman)";
      homepage = "https://github.com/cet-t/taskman";
      license = lib.licenses.mit;
      mainProgram = "taskman";
      platforms = lib.platforms.linux;
    };
  }
  // lib.optionalAttrs withPrivilegedHelper {
    TASKMAN_PRIVILEGED_HELPER_PATH = "${placeholder "out"}/libexec/taskman-privileged-helper";
  }
)
