//! App update checking API exposed to Flutter via FRB.

use std::io::Read;
use std::path::Path;
use std::sync::RwLock;
use std::time::{SystemTime, UNIX_EPOCH};

use flutter_rust_bridge::frb;
use serde::Deserialize;

use crate::net::{fetch_text, is_allowed_release_url, DEFAULT_HTTP_MAX_REDIRECTS};

/// Minimum interval between update checks (6 hours).
const UPDATE_CHECK_INTERVAL_MS: u64 = 6 * 60 * 60 * 1000;

const LATEST_JSON_URL: &str =
    "https://github.com/g1mliii/compact-games/releases/latest/download/latest.json";

const MAX_BODY_BYTES: u64 = 512 * 1024; // 512 KB
const USER_AGENT: &str = "CompactGames-Updater/1";

static LAST_CHECK_MS: RwLock<u64> = RwLock::new(0);
static LAST_RESULT: RwLock<Option<UpdateCheckResult>> = RwLock::new(None);

/// Result of an update check, returned to Flutter.
#[derive(Clone)]
#[frb(dart_metadata=("freezed"))]
pub struct UpdateCheckResult {
    pub update_available: bool,
    pub latest_version: String,
    pub download_url: String,
    pub release_notes: String,
    pub checksum_sha256: String,
    pub published_at: String,
}

/// Wire format of the `latest.json` release manifest.
#[derive(Deserialize)]
struct LatestManifest {
    version: String,
    download_url: String,
    #[serde(default)]
    checksum_sha256: String,
    #[serde(default)]
    release_notes: String,
    #[serde(default)]
    published_at: String,
}

/// Check GitHub Releases for a newer app version.
///
/// Rate-limited to one check per 6 hours. If called within the window,
/// returns the cached result without hitting the network.
pub fn check_for_update(current_version: String) -> Result<UpdateCheckResult, String> {
    let now_ms = now_millis();

    if let Some(result) = cached_result_within_interval(now_ms) {
        return Ok(result);
    }

    let body = fetch_text(LATEST_JSON_URL, USER_AGENT, MAX_BODY_BYTES)?;
    let manifest: LatestManifest =
        serde_json::from_str(&body).map_err(|e| format!("Invalid latest.json: {e}"))?;

    if !is_allowed_download_url(&manifest.download_url) {
        return Err(format!(
            "Manifest download_url is not from an allowed origin: {}",
            manifest.download_url
        ));
    }

    let result = UpdateCheckResult {
        update_available: is_newer(&manifest.version, &current_version),
        latest_version: manifest.version,
        download_url: manifest.download_url,
        release_notes: manifest.release_notes,
        checksum_sha256: manifest.checksum_sha256,
        published_at: manifest.published_at,
    };

    if let Ok(mut guard) = LAST_RESULT.write() {
        *guard = Some(result.clone());
    }
    if let Ok(mut guard) = LAST_CHECK_MS.write() {
        *guard = now_ms;
    }

    Ok(result)
}

fn cached_result_within_interval(now_ms: u64) -> Option<UpdateCheckResult> {
    let last = LAST_CHECK_MS.read().map(|g| *g).unwrap_or(0);
    if last == 0 || now_ms.saturating_sub(last) >= UPDATE_CHECK_INTERVAL_MS {
        return None;
    }

    LAST_RESULT.read().ok().and_then(|cached| cached.clone())
}

/// Download an update installer to `dest_path`, verifying SHA-256 checksum.
///
/// Downloads to a `.tmp` sibling first, verifies the hash, then renames.
/// Returns the final path on success.
pub fn download_update(
    url: String,
    dest_path: String,
    expected_sha256: String,
) -> Result<String, String> {
    use sha2::{Digest, Sha256};
    use std::fs;

    if !is_allowed_download_url(&url) {
        return Err(format!("Download URL is not from an allowed origin: {url}"));
    }

    let dest = Path::new(&dest_path);
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create directory {}: {e}", parent.display()))?;
    }

    let tmp_path = dest.with_extension("tmp");

    // Resolve final URL through redirects (GitHub releases use them).
    // Use a short timeout — HEAD requests should resolve in seconds.
    let final_url = resolve_redirects(&url, 15)?;

    let agent = ureq::Agent::new_with_config(
        ureq::config::Config::builder()
            .timeout_global(Some(std::time::Duration::from_secs(300)))
            .build(),
    );

    let response = agent
        .get(&final_url)
        .header("User-Agent", USER_AGENT)
        .call()
        .map_err(|e| format!("Download failed: {e}"))?;

    let status = response.status().as_u16();
    if status != 200 {
        return Err(format!("Unexpected HTTP status: {status}"));
    }

    // Stream to temp file while computing hash.
    let mut file =
        fs::File::create(&tmp_path).map_err(|e| format!("Failed to create temp file: {e}"))?;
    let mut hasher = Sha256::new();
    let mut reader = response.into_body().into_reader();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = reader
            .read(&mut buf)
            .map_err(|e| format!("Download read error: {e}"))?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
        std::io::Write::write_all(&mut file, &buf[..n]).map_err(|e| format!("Write error: {e}"))?;
    }
    drop(file);

    // Verify checksum.
    if !expected_sha256.is_empty() {
        let actual = format!("{:x}", hasher.finalize());
        if !actual.eq_ignore_ascii_case(&expected_sha256) {
            let _ = fs::remove_file(&tmp_path);
            return Err(format!(
                "Checksum mismatch: expected {expected_sha256}, got {actual}"
            ));
        }
    }

    replace_existing_file(&tmp_path, dest)?;

    Ok(dest_path)
}

fn replace_existing_file(from: &Path, to: &Path) -> Result<(), String> {
    if to.exists() {
        std::fs::remove_file(to)
            .map_err(|e| format!("Failed to replace existing installer {}: {e}", to.display()))?;
    }

    std::fs::rename(from, to).map_err(|e| format!("Failed to rename temp file: {e}"))
}

fn is_allowed_download_url(url: &str) -> bool {
    is_allowed_release_url(url)
}

/// Simple semver comparison: returns true if `latest` is newer than `current`.
fn is_newer(latest: &str, current: &str) -> bool {
    let parse = |s: &str| -> (u32, u32, u32) {
        let s = s.trim().trim_start_matches('v');
        let parts: Vec<&str> = s.split('.').collect();
        let major = parts.first().and_then(|p| p.parse().ok()).unwrap_or(0);
        let minor = parts.get(1).and_then(|p| p.parse().ok()).unwrap_or(0);
        let patch = parts.get(2).and_then(|p| p.parse().ok()).unwrap_or(0);
        (major, minor, patch)
    };
    parse(latest) > parse(current)
}

/// Resolve a URL through redirects, returning the final URL.
/// Uses HEAD requests to avoid downloading the body.
fn resolve_redirects(url: &str, timeout_secs: u64) -> Result<String, String> {
    let agent = ureq::Agent::new_with_config(
        ureq::config::Config::builder()
            .timeout_global(Some(std::time::Duration::from_secs(timeout_secs)))
            .build(),
    );

    let mut next_url = url.to_string();
    for _ in 0..=DEFAULT_HTTP_MAX_REDIRECTS {
        let response = agent
            .head(&next_url)
            .header("User-Agent", USER_AGENT)
            .call()
            .map_err(|e| format!("HTTP request failed: {e}"))?;

        let status = response.status().as_u16();
        if (300..400).contains(&status) {
            let location = response
                .headers()
                .get("location")
                .and_then(|v| v.to_str().ok())
                .ok_or_else(|| format!("Redirect ({status}) missing Location header"))?;
            next_url = location.to_string();
            continue;
        }

        return Ok(next_url);
    }

    Err("Too many redirects".to_string())
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_newer() {
        assert!(is_newer("0.2.0", "0.1.0"));
        assert!(is_newer("1.0.0", "0.9.9"));
        assert!(is_newer("0.1.1", "0.1.0"));
        assert!(!is_newer("0.1.0", "0.1.0"));
        assert!(!is_newer("0.0.9", "0.1.0"));
        assert!(is_newer("v1.0.0", "0.9.0"));
    }

    #[test]
    fn test_cached_result_is_reused_while_rate_limited() {
        let cached = UpdateCheckResult {
            update_available: true,
            latest_version: "0.2.0".to_string(),
            download_url: "https://example.invalid/download".to_string(),
            release_notes: "Bug fixes".to_string(),
            checksum_sha256: "abc123".to_string(),
            published_at: "2026-04-04T00:00:00Z".to_string(),
        };

        *LAST_CHECK_MS.write().unwrap() = UPDATE_CHECK_INTERVAL_MS;
        *LAST_RESULT.write().unwrap() = Some(cached);

        let reused = cached_result_within_interval(UPDATE_CHECK_INTERVAL_MS + 1)
            .expect("cached result should be reused");

        assert_eq!(reused.latest_version, "0.2.0");
        assert!(reused.update_available);
        assert_eq!(reused.checksum_sha256, "abc123");

        *LAST_CHECK_MS.write().unwrap() = 0;
        *LAST_RESULT.write().unwrap() = None;
    }

    #[test]
    fn test_replace_existing_file_overwrites_destination() {
        let temp_dir = tempfile::tempdir().expect("temp dir");
        let src = temp_dir.path().join("download.tmp");
        let dest = temp_dir.path().join("installer.exe");

        std::fs::write(&src, b"new installer").expect("write src");
        std::fs::write(&dest, b"old installer").expect("write dest");

        replace_existing_file(&src, &dest).expect("replace file");

        assert!(!src.exists());
        assert_eq!(
            std::fs::read_to_string(&dest).expect("read dest"),
            "new installer"
        );
    }

    #[test]
    fn test_allowed_download_url() {
        assert!(is_allowed_download_url(
            "https://github.com/g1mliii/compact-games/releases/download/v0.1.0/CompactGames-Setup-0.1.0.exe"
        ));
        assert!(is_allowed_download_url(
            "https://github.com/g1mliii/compact-games/releases/latest/download/CompactGames-Setup.exe"
        ));
        assert!(!is_allowed_download_url(
            "https://evil.com/g1mliii/compact-games/releases/download/malware.exe"
        ));
        assert!(!is_allowed_download_url(
            "http://github.com/g1mliii/compact-games/releases/download/v0.1.0/file.exe"
        ));
        assert!(!is_allowed_download_url(
            "https://github.com/other-repo/releases/download/file.exe"
        ));
        assert!(!is_allowed_download_url(""));
    }
}
