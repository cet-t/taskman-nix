//! Detached process-group launches and trust checks for privileged execution.

use std::ffi::{OsStr, OsString};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};

use tm_core::error::{Result, TmError};

pub(super) fn spawn_detached(
    program: &OsStr,
    arguments: &[OsString],
    environment: &[(String, String)],
) -> Result<()> {
    build_command(program, arguments, environment)
        .spawn()
        .map(|_| ())
        .map_err(|error| {
            TmError::platform(
                "launch",
                format!("could not start {}: {error}", program.to_string_lossy()),
            )
        })
}

/// Start a program in its own process group and reap it from a short helper
/// thread without keeping the caller's action lane occupied for the program's
/// lifetime.
pub(super) fn spawn_detached_reaped(
    program: &OsStr,
    arguments: &[OsString],
    environment: &[(String, String)],
) -> Result<()> {
    let child = build_command(program, arguments, environment)
        .spawn()
        .map_err(|error| {
            TmError::platform(
                "launch",
                format!("could not start {}: {error}", program.to_string_lossy()),
            )
        })?;
    reaping_thread(child)
}

fn build_command(
    program: &OsStr,
    arguments: &[OsString],
    environment: &[(String, String)],
) -> Command {
    let mut command = Command::new(program);
    command.args(arguments);
    if !environment.is_empty() {
        command.env_clear();
        command.envs(environment.iter().map(|(name, value)| (name, value)));
    }
    command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0);
    command
}

fn reaping_thread(child: Child) -> Result<()> {
    let child = Arc::new(Mutex::new(Some(child)));
    let waiter_child = child.clone();
    let spawned = std::thread::Builder::new()
        .name("tm-linux-launch-wait".into())
        .spawn(move || {
            let child = waiter_child.lock().ok().and_then(|mut child| child.take());
            if let Some(mut child) = child {
                let _ = child.wait();
            }
        });
    match spawned {
        Ok(_) => Ok(()),
        Err(error) => {
            if let Some(mut child) = child.lock().ok().and_then(|mut child| child.take()) {
                let _ = child.kill();
                let _ = child.wait();
            }
            Err(TmError::platform(
                "launch",
                format!("could not start the child-reaping thread: {error}"),
            ))
        }
    }
}

/// Require a canonical system-tool path and every parent directory to be
/// root-owned and not group/other writable (with the narrow NixOS exception for
/// the sticky, non-world-writable `/nix/store` root directory, while every
/// store entry and binary beneath it remains strictly root-owned and
/// non-writable). This prevents a writable PATH or replaced helper from
/// participating in the elevation request.
pub(super) fn trusted_system_program(path: &Path) -> Result<PathBuf> {
    if !path.is_absolute() {
        Err(TmError::platform(
            "trusted system program",
            "program path must be absolute",
        ))
    } else {
        trust_executable(path)
    }
}

fn trust_executable(path: &Path) -> Result<PathBuf> {
    let canonical = std::fs::canonicalize(path).map_err(|error| {
        TmError::platform(
            "trusted system program",
            format!("cannot resolve {}: {error}", path.display()),
        )
    })?;
    let exe_metadata = std::fs::metadata(&canonical).map_err(|error| {
        TmError::platform(
            "trusted system program",
            format!("cannot inspect {}: {error}", canonical.display()),
        )
    })?;
    let exe_mode = exe_metadata.permissions().mode();
    if !is_trusted_executable_file(exe_metadata.uid(), exe_mode, exe_metadata.is_file()) {
        return Err(TmError::platform(
            "trusted system program",
            format!(
                "{} is not a trusted root-owned executable regular file",
                canonical.display()
            ),
        ));
    }
    let Some(parent) = canonical.parent() else {
        return Err(TmError::platform(
            "trusted system program",
            format!("{} has no parent directory", canonical.display()),
        ));
    };
    for component in parent.ancestors() {
        let metadata = std::fs::metadata(component).map_err(|error| {
            TmError::platform(
                "trusted system program",
                format!("cannot inspect {}: {error}", component.display()),
            )
        })?;
        let mode = metadata.permissions().mode();
        if !is_trusted_parent_dir(component, metadata.uid(), mode, metadata.is_dir()) {
            return Err(TmError::platform(
                "trusted system program",
                format!(
                    "refusing to run a program from a non-root-owned or writable path: {}",
                    component.display()
                ),
            ));
        }
    }
    Ok(canonical)
}

fn is_trusted_executable_file(uid: u32, mode: u32, is_file: bool) -> bool {
    is_file && uid == 0 && mode & 0o022 == 0 && mode & 0o111 != 0
}

fn is_trusted_parent_dir(path: &Path, uid: u32, mode: u32, is_dir: bool) -> bool {
    if !is_dir || uid != 0 {
        return false;
    }
    if mode & 0o022 == 0 {
        return true;
    }
    // Multi-user NixOS mounts `/nix/store` as `root:nixbld` mode `1775`
    // (sticky + group-writable for nixbld workers). Every store path beneath
    // `/nix/store` is still checked by the strict rule above.
    path == Path::new("/nix/store") && mode & 0o002 == 0 && mode & 0o1000 != 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trusted_system_programs_must_be_absolute() {
        assert!(trusted_system_program(Path::new("./local-program")).is_err());
        assert!(trusted_system_program(Path::new("../local-program")).is_err());
    }

    #[test]
    fn nix_store_parent_policy_matches_nixos_multi_user_permissions() {
        let nix_store = Path::new("/nix/store");
        assert!(is_trusted_parent_dir(nix_store, 0, 0o1775, true));
        assert!(is_trusted_parent_dir(Path::new("/nix"), 0, 0o755, true));
        assert!(is_trusted_parent_dir(
            Path::new("/nix/store/pkg-1/bin"),
            0,
            0o555,
            true
        ));
        assert!(!is_trusted_parent_dir(nix_store, 0, 0o0775, true));
        assert!(!is_trusted_parent_dir(nix_store, 0, 0o1777, true));
        assert!(!is_trusted_parent_dir(nix_store, 1000, 0o1775, true));
        assert!(!is_trusted_parent_dir(
            Path::new("/nix/store/pkg-1"),
            0,
            0o1775,
            true
        ));
        assert!(!is_trusted_parent_dir(Path::new("/tmp"), 0, 0o1775, true));
    }

    #[test]
    fn executable_trust_allows_setuid_root_wrappers_and_rejects_writable_files() {
        assert!(is_trusted_executable_file(0, 0o4511, true));
        assert!(is_trusted_executable_file(0, 0o555, true));
        assert!(!is_trusted_executable_file(0, 0o775, true));
        assert!(!is_trusted_executable_file(1000, 0o755, true));
        assert!(!is_trusted_executable_file(0, 0o644, true));
        assert!(!is_trusted_executable_file(0, 0o755, false));
    }
}
