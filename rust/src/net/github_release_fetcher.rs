use std::fs;
use std::path::Path;
use std::time::{Duration, SystemTime};

use serde::de::DeserializeOwned;
use serde::Deserialize;
use sha2::{Digest, Sha256};

use super::{fetch_text, is_allowed_release_url};

const DEFAULT_MAX_BODY_BYTES: u64 = 8 * 1024 * 1024;

#[derive(Clone, Copy)]
pub struct ReleaseJsonAsset<'a> {
    pub asset_url: &'a str,
    pub bundle_url: &'a str,
    pub cache_path: &'a Path,
    pub ttl: Duration,
    pub user_agent: &'a str,
    pub max_body_bytes: u64,
}

#[derive(Debug, Deserialize)]
struct ReleaseAssetBundle {
    sha256: String,
}

pub fn fetch_signed_release_asset<T>(config: ReleaseJsonAsset<'_>) -> Result<T, String>
where
    T: DeserializeOwned,
{
    if cache_is_fresh(config.cache_path, config.ttl) {
        if let Ok(parsed) = read_cached_json(config.cache_path) {
            return Ok(parsed);
        }
    }

    match fetch_and_cache_signed_asset(&config) {
        Ok(parsed) => Ok(parsed),
        Err(network_error) => match read_cached_json(config.cache_path) {
            Ok(parsed) => {
                log::warn!(
                    "Using cached release asset after refresh failure for {}: {network_error}",
                    config.asset_url
                );
                Ok(parsed)
            }
            Err(cache_error) => Err(format!(
                "{network_error}; cached asset unavailable: {cache_error}"
            )),
        },
    }
}

fn fetch_and_cache_signed_asset<T>(config: &ReleaseJsonAsset<'_>) -> Result<T, String>
where
    T: DeserializeOwned,
{
    validate_release_url(config.asset_url)?;
    validate_release_url(config.bundle_url)?;

    let bundle_body = fetch_text(
        config.bundle_url,
        config.user_agent,
        config.max_body_bytes.min(DEFAULT_MAX_BODY_BYTES),
    )?
    .ok_or_else(|| format!("Asset bundle not found at {}", config.bundle_url))?;
    let bundle: ReleaseAssetBundle =
        serde_json::from_str(&bundle_body).map_err(|e| format!("Invalid asset bundle: {e}"))?;
    if bundle.sha256.trim().is_empty() {
        return Err("Asset bundle did not include sha256".to_string());
    }

    let asset_body = fetch_text(config.asset_url, config.user_agent, config.max_body_bytes)?
        .ok_or_else(|| format!("Release asset not found at {}", config.asset_url))?;
    verify_sha256(asset_body.as_bytes(), &bundle.sha256)?;
    let parsed: T = serde_json::from_str(&asset_body)
        .map_err(|e| format!("Invalid release asset JSON: {e}"))?;

    if let Some(parent) = config.cache_path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create release asset cache dir: {e}"))?;
    }
    crate::utils::atomic_write(config.cache_path, asset_body.as_bytes())
        .map_err(|e| format!("Failed to write release asset cache: {e}"))?;

    Ok(parsed)
}

pub fn verify_sha256(bytes: &[u8], expected_sha256: &str) -> Result<(), String> {
    let actual = format!("{:x}", Sha256::digest(bytes));
    if actual.eq_ignore_ascii_case(expected_sha256.trim()) {
        Ok(())
    } else {
        Err(format!(
            "Checksum mismatch: expected {}, got {actual}",
            expected_sha256.trim()
        ))
    }
}

fn read_cached_json<T>(path: &Path) -> Result<T, String>
where
    T: DeserializeOwned,
{
    let bytes = fs::read(path).map_err(|e| format!("Failed to read cache: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| format!("Invalid cached JSON: {e}"))
}

fn cache_is_fresh(path: &Path, ttl: Duration) -> bool {
    let Ok(metadata) = fs::metadata(path) else {
        return false;
    };
    let Ok(modified) = metadata.modified() else {
        return false;
    };
    SystemTime::now()
        .duration_since(modified)
        .map(|age| age < ttl)
        .unwrap_or(false)
}

fn validate_release_url(url: &str) -> Result<(), String> {
    if is_allowed_release_url(url) {
        Ok(())
    } else {
        Err(format!(
            "Release asset URL is not from an allowed origin: {url}"
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn verify_sha256_accepts_matching_hash() {
        verify_sha256(
            b"compact games",
            "9581b6b80155fd579ca0b311f0b1efd86a482f1bd2bbfbc0ccbe2c47a071c06e",
        )
        .expect("hash should match");
    }

    #[test]
    fn verify_sha256_rejects_mismatch() {
        let error = verify_sha256(b"compact games", "deadbeef").unwrap_err();
        assert!(error.contains("Checksum mismatch"));
    }
}
