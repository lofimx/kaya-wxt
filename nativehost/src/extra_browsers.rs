//! Install/uninstall native messaging manifests for browsers not covered by
//! the `native_messaging` crate (e.g. Chrome for Testing).

use std::path::Path;
use std::{fs, io};

/// Extra Chromium-based browser directories not covered by the native_messaging crate.
/// Each entry is the NativeMessagingHosts directory relative to the user's home.
#[cfg(target_os = "linux")]
const EXTRA_CHROMIUM_DIRS: &[&str] = &[".config/google-chrome-for-testing/NativeMessagingHosts"];

#[cfg(target_os = "macos")]
const EXTRA_CHROMIUM_DIRS: &[&str] =
    &["Library/Application Support/Google/Chrome for Testing/NativeMessagingHosts"];

#[cfg(target_os = "windows")]
const EXTRA_CHROMIUM_DIRS: &[&str] = &[];

/// Copy the Chrome native messaging manifest to extra browser directories.
///
/// Reads the manifest that the `native_messaging` crate wrote for Chrome and
/// copies it verbatim into each directory listed in `EXTRA_CHROMIUM_DIRS`.
pub fn install_extra(host_name: &str) -> io::Result<()> {
    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return Ok(()),
    };

    let chrome_manifest_path = chrome_manifest_path(&home, host_name);
    if !chrome_manifest_path.exists() {
        return Ok(());
    }

    let manifest_content = fs::read(&chrome_manifest_path)?;
    for extra_dir in EXTRA_CHROMIUM_DIRS {
        let target_dir = home.join(extra_dir);
        if let Err(e) = fs::create_dir_all(&target_dir) {
            eprintln!("Warning: could not create {}: {}", target_dir.display(), e);
            continue;
        }
        let target_path = target_dir.join(format!("{host_name}.json"));
        fs::write(&target_path, &manifest_content)?;
        println!("  Copied manifest to {}", target_path.display());
    }

    Ok(())
}

/// Remove the native messaging manifest from extra browser directories.
pub fn uninstall_extra(host_name: &str) -> io::Result<()> {
    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return Ok(()),
    };

    for extra_dir in EXTRA_CHROMIUM_DIRS {
        let target_path = home.join(extra_dir).join(format!("{host_name}.json"));
        if target_path.exists() {
            fs::remove_file(&target_path)?;
            println!("  Removed {}", target_path.display());
        }
    }

    Ok(())
}

#[cfg(target_os = "linux")]
fn chrome_manifest_path(home: &Path, host_name: &str) -> std::path::PathBuf {
    home.join(".config/google-chrome/NativeMessagingHosts")
        .join(format!("{host_name}.json"))
}

#[cfg(target_os = "macos")]
fn chrome_manifest_path(home: &Path, host_name: &str) -> std::path::PathBuf {
    home.join("Library/Application Support/Google/Chrome/NativeMessagingHosts")
        .join(format!("{host_name}.json"))
}

#[cfg(target_os = "windows")]
fn chrome_manifest_path(home: &Path, host_name: &str) -> std::path::PathBuf {
    // On Windows the native_messaging crate uses the registry, not a file path
    // relative to home. Return a path that won't exist so install_extra is a no-op.
    home.join(format!("{host_name}.json"))
}
