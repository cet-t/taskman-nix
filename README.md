# TaskMan (NixOS Fork)

A fast, native-feeling Task Manager and system monitor in Rust, adapted and
packaged for **NixOS** (Wayland & X11).

This repository is a NixOS-focused fork of
[aufkrawall/taskman](https://github.com/aufkrawall/taskman) (MIT License).
Upstream Windows and macOS support is preserved in-tree so upstream fixes can
continue to be integrated cleanly.

## What this fork adds for NixOS

- **Nix Flake & declarative modules** (`flake.nix`, `nix/`): reproducible
  packages (`x86_64-linux`, `aarch64-linux`), `overlays.default`,
  `nixosModules.default`, `homeManagerModules.default`, `devShells.default`,
  and `checks` (including headless `--selfcheck --mock`).
- **NixOS `/nix/store` trust-chain support**: allows immutable, root-owned store
  binaries beneath multi-user `/nix/store` (`1775 root:nixbld`, sticky bit
  required and verified) while keeping strict ownership/writability checks on
  every store entry and executable.
- **Non-FHS system utility resolution**: resolves `systemctl`, `loginctl`,
  `fc-match`, and `/run/wrappers/bin/pkexec` on NixOS, with build-time store
  path pinning for non-setuid tools and `xdg-utils` / Wayland / X11 / Vulkan /
  OpenGL runtime library wrapping.
- **NixOS-safe XDG autostart & icons**: prefers stable profile paths
  (`/run/current-system/sw/bin/taskman`, `~/.nix-profile/bin/taskman`,
  `/etc/profiles/per-user/$USER/bin/taskman`) over ephemeral `/nix/store` paths
  when generating autostart entries, and searches `$XDG_DATA_DIRS/pixmaps` for
  legacy icons.
- **Fork-scoped App ID**: uses `io.github.cet_t.Taskman` (`.desktop` entry,
  Wayland `app_id`, X11 `WM_CLASS`, and XDG autostart entry) to avoid desktop
  entry collisions with upstream builds.
- **Native Linux test & lint fixes**: fixes pre-existing Linux-only test and
  clippy issues so the full Linux test suite passes natively on NixOS and CI.

## Highlights

- **Processes** — grouped presentation (Apps / Background / System) using
  EWMH X11 window evidence and native Wayland systemd/launcher evidence, with
  CPU, memory, disk I/O, search, multi-select, and PID-reuse-safe actions.
- **Performance** — overall and per-logical-processor CPU graphs (including
  kernel time), memory, per-disk stats, per-adapter network metadata
  (IPv4/IPv6/driver), and DRM GPU telemetry.
- **Details & Process Properties** — literal PPID tree or flat table, typed
  persisted column catalog, threads, memory-mapped modules (read-only), TCP/UDP
  connections, and open file handles.
- **Services, Users & Startup** — systemd unit listing and on-demand Polkit
  service control (`systemctl` via `/run/wrappers/bin/pkexec`), `loginctl`
  sessions, and XDG autostart management.
- **Honest missing telemetry** — unavailable metrics render as `—` / `Unknown`,
  never as fabricated zeros.
- **Sub-pixel (LCD) text & CPU/Vulkan renderers** — ships the vendored egui
  fork (`vendor/egui`, tag 0.36.1) with fontconfig-driven RGB/BGR LCD text
  rendering on both the native CPU renderer (default) and Vulkan WGPU.

## Installing on NixOS

### Try immediately

```bash
nix run github:cet-t/taskman
```

### NixOS module (`flake.nix`)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    taskman = {
      url = "github:cet-t/taskman";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, taskman, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        taskman.nixosModules.default
        {
          programs.taskman.enable = true;
        }
      ];
    };
  };
}
```

### Home Manager module

```nix
{
  imports = [ inputs.taskman.homeManagerModules.default ];

  programs.taskman = {
    enable = true;
    autostart = true; # declarative ~/.config/autostart/io.github.cet_t.Taskman.desktop
  };
}
```

### Overlay

```nix
nixpkgs.overlays = [ inputs.taskman.overlays.default ];
# then use pkgs.taskman
```

## Building & Development

```bash
# Enter the Nix development shell (rustc, cargo, clippy, rustfmt, runtime libs)
nix develop

# Fast local test & lint loop
cargo test -p tm-core -p tm-platform -p tm-ui -p tm-app
cargo clippy -p tm-core -p tm-platform -p tm-ui -p tm-app --all-targets --all-features -- -D warnings
cargo fmt --all -- --check

# Reproducible Nix package build & checks
nix flake check
nix build

# Headless sampling smoke test (prints JSON summary)
./result/bin/taskman --selfcheck
```

## Keyboard shortcuts

Press <kbd>F1</kbd> inside the app for the complete localized shortcut overlay.

| Keys | Action |
| --- | --- |
| <kbd>F5</kbd> | Refresh data |
| <kbd>F6</kbd> / <kbd>Shift</kbd>+<kbd>F6</kbd> | Cycle search box, sidebar, command buttons, and content |
| <kbd>Ctrl</kbd>+<kbd>F</kbd> / <kbd>Alt</kbd>+<kbd>F</kbd> | Focus search |
| <kbd>Ctrl</kbd>+<kbd>Tab</kbd> / <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Tab</kbd> | Next / previous page |
| <kbd>Ctrl</kbd>+<kbd>1</kbd>…<kbd>9</kbd> | Jump directly to page 1–9 |
| <kbd>Ctrl</kbd>+<kbd>,</kbd> | Settings |
| <kbd>Ctrl</kbd>+<kbd>N</kbd> | Run new task |
| <kbd>Del</kbd> | End selected processes (with confirmation) |
| <kbd>Menu</kbd> / <kbd>Shift</kbd>+<kbd>F10</kbd> | Open context menu |
| <kbd>F1</kbd> | Show or hide shortcut help |

## Diagnostics

| Environment variable | Effect |
| --- | --- |
| `TASKMAN_RENDERER=cpu\|vulkan\|opengl\|software\|wgpu` | Pin one compiled renderer backend |
| `TASKMAN_GPU=cpu\|vulkan` | Override saved renderer preference for one run (fallbacks allowed) |
| `TASKMAN_SUBPIXEL=0\|1` | Disable or request sub-pixel text (bounded by renderer/fontconfig capability) |
| `TASKMAN_FPS_PROBE=1` | Continuous repaints + FPS overlay |
| `TASKMAN_DIALOG=settings\|run` | Open a dialog at startup |
| `TASKMAN_PERF=<key>` | Preselect a Performance resource |
| `TASKMAN_DATA_DIR` / `TASKMAN_CONFIG_DIR` | Isolate data/config directories |
| `TASKMAN_AUTOSTART_EXEC=<path>` | Override executable path written to the XDG autostart entry |

## Known limitations on NixOS / Linux

- **Privileged per-process actions** (killing/suspending other users' processes
  or raising nice priority into negative values) are currently fail-closed
  without running as root. A dedicated, minimal Polkit helper binary + NixOS
  policy integration is planned as a follow-up phase. Systemd service control
  already supports on-demand Polkit authentication via `/run/wrappers/bin/pkexec`.
- **Native Wayland window inventory**: Wayland does not expose a portable
  whole-desktop window list, so native Wayland Apps are classified via systemd
  `app.slice` / launcher metadata while XWayland apps use EWMH.
- **No Linux system tray**: the window starts visibly.

## Repository layout

| Path | What it is |
| --- | --- |
| `flake.nix`, `nix/` | Nix Flake, package derivation, overlay, NixOS & Home Manager modules |
| `crates/tm-core` | Platform-agnostic model, engine, settings, app history, i18n |
| `crates/tm-platform` | OS collectors and actions behind traits (`linux/`, `win/`, `macos/`) |
| `crates/tm-ui` | Shared theme palette and font setup |
| `crates/tm-app` | The eframe GUI (`taskman`) |
| `crates/tm-service`, `crates/tm-installer` | Upstream Windows service and installer crates (preserved for upstream parity) |
| `vendor/egui`, `vendor/winit` | Vendored upstream forks (sub-pixel text, CPU renderer, winit patches) |

## Attribution & License

- Original project: [aufkrawall/taskman](https://github.com/aufkrawall/taskman),
  Copyright (c) 2026 aufkrawall.
- NixOS fork modifications: Copyright (c) 2026 cet-t.
- Licensed under the **MIT License** — see [LICENSE](LICENSE).
- Vendored third-party crates retain their original licenses:
  - `vendor/egui`: `MIT OR Apache-2.0`
  - `vendor/winit`: `Apache-2.0`
