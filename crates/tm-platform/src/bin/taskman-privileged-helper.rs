//! Minimal, GUI-free privileged action helper for packaged Linux/NixOS installs.
//!
//! Invoked on demand by Polkit (`pkexec`) to execute a single identity-checked
//! process operation (`kill`, `suspend`, `resume`, `set-priority`,
//! `set-affinity`) or systemd service action, then exits immediately. Keeping
//! this binary separate from the GUI keeps eframe/winit/wgpu/Wayland/X11 and
//! any runtime library wrapper scripts completely outside the root attack
//! surface.

#![deny(unsafe_op_in_unsafe_fn)]

#[cfg(target_os = "linux")]
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    std::process::exit(tm_platform::linux::polkit::run_standalone_helper(&args));
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("taskman-privileged-helper is only supported on Linux");
    std::process::exit(1);
}
