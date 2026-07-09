//! Unsupported games API exposed to Flutter via FRB.

use std::path::Path;

use flutter_rust_bridge::frb;
use serde::Deserialize;

use crate::net::github_release_fetcher::verify_sha256;
use crate::safety::unsupported_games;

const COMMUNITY_LIST_BUNDLE_ENDPOINT: &str =
    "https://github.com/g1mliii/compact-games/releases/latest/download/unsupported_games.bundle.json";
const COMMUNITY_LIST_BUNDLE_VERSION: u32 = 1;
const COMMUNITY_LIST_ASSET_NAME: &str = "unsupported_games.json";
const MAX_COMMUNITY_LIST_BODY_BYTES: u64 = 1024 * 1024;

#[derive(Deserialize)]
struct CommunityListBundle {
    version: u32,
    asset: String,
    sha256: String,
}

/// Report a game as unsupported (user-reported, persisted locally).
#[frb(sync)]
pub fn report_unsupported_game(path: String) {
    if path.trim().is_empty() {
        return;
    }
    unsupported_games::report_unsupported_game(Path::new(&path));
}

/// Remove a game from the user-reported unsupported list.
#[frb(sync)]
pub fn unreport_unsupported_game(path: String) {
    if path.trim().is_empty() {
        return;
    }
    unsupported_games::unreport_unsupported_game(Path::new(&path));
}

/// Check if a game is in any unsupported list.
#[frb(sync)]
pub fn is_unsupported(game_path: String) -> bool {
    unsupported_games::is_unsupported_game(Path::new(&game_path))
}

/// Prepare the local unsupported-report payload and best-effort submit it when
/// an ingest endpoint is configured.
///
/// Returns the number of stable local report candidates currently included.
pub fn sync_unsupported_report_collection(app_version: String) -> Result<u32, String> {
    unsupported_games::sync_report_collection(&app_version)
}

/// Fetch a verified community unsupported games list from GitHub Releases and update the local cache.
/// Returns the number of games in the updated list, or an error message.
pub fn fetch_community_unsupported_list() -> Result<u32, String> {
    if !unsupported_games::should_fetch_community_list() {
        return Ok(unsupported_games::community_list_len());
    }

    let Some(bundle_body) = crate::net::fetch_text(
        COMMUNITY_LIST_BUNDLE_ENDPOINT,
        "CompactGames-Community-List/1",
        MAX_COMMUNITY_LIST_BODY_BYTES,
    )?
    else {
        // 404: the signed bundle is not yet attached to the latest release.
        // Mark fetched so we don't retry on every check, and preserve the cache.
        unsupported_games::mark_community_list_fetched()?;
        return Ok(unsupported_games::community_list_len());
    };

    let Some(asset_body) = crate::net::fetch_text(
        unsupported_games::DEFAULT_COMMUNITY_LIST_ENDPOINT,
        "CompactGames-Community-List/1",
        MAX_COMMUNITY_LIST_BODY_BYTES,
    )?
    else {
        // 404: list asset not yet attached to the latest release. Mark fetched
        // so we don't retry on every check, and return whatever's cached.
        unsupported_games::mark_community_list_fetched()?;
        return Ok(unsupported_games::community_list_len());
    };

    let games = parse_verified_community_list(&bundle_body, &asset_body)?;
    let count = games.len() as u32;

    unsupported_games::update_community_list(games)?;
    unsupported_games::mark_community_list_fetched()?;
    Ok(count)
}

fn parse_verified_community_list(
    bundle_body: &str,
    asset_body: &str,
) -> Result<Vec<String>, String> {
    let bundle: CommunityListBundle = serde_json::from_str(bundle_body)
        .map_err(|error| format!("Invalid community bundle: {error}"))?;

    if bundle.version != COMMUNITY_LIST_BUNDLE_VERSION {
        return Err(format!(
            "Unsupported community bundle version: expected {COMMUNITY_LIST_BUNDLE_VERSION}, got {}",
            bundle.version
        ));
    }
    if bundle.asset != COMMUNITY_LIST_ASSET_NAME {
        return Err(format!(
            "Unexpected community bundle asset: expected {COMMUNITY_LIST_ASSET_NAME}, got {}",
            bundle.asset
        ));
    }

    verify_sha256(asset_body.as_bytes(), &bundle.sha256)?;
    serde_json::from_str(asset_body)
        .map_err(|error| format!("Invalid community list JSON: {error}"))
}

#[cfg(test)]
mod tests {
    use sha2::{Digest, Sha256};

    use super::*;

    fn bundle_for(asset_body: &str) -> String {
        let sha256 = Sha256::digest(asset_body.as_bytes())
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        serde_json::json!({
            "version": COMMUNITY_LIST_BUNDLE_VERSION,
            "asset": COMMUNITY_LIST_ASSET_NAME,
            "sha256": sha256,
        })
        .to_string()
    }

    #[test]
    fn verified_community_list_accepts_matching_bundle() {
        let asset_body = "[\"safe-game\",\"another-game\"]\n";

        let games = parse_verified_community_list(&bundle_for(asset_body), asset_body)
            .expect("matching bundle should parse");

        assert_eq!(games, vec!["safe-game", "another-game"]);
    }

    #[test]
    fn verified_community_list_rejects_tampered_asset() {
        let bundle = bundle_for("[\"safe-game\"]\n");

        let error = parse_verified_community_list(&bundle, "[\"tampered-game\"]\n")
            .expect_err("tampered asset must be rejected");

        assert!(error.contains("Checksum mismatch"));
    }

    #[test]
    fn verified_community_list_rejects_unknown_bundle_version() {
        let asset_body = "[\"safe-game\"]\n";
        let mut bundle: serde_json::Value = serde_json::from_str(&bundle_for(asset_body)).unwrap();
        bundle["version"] = serde_json::json!(COMMUNITY_LIST_BUNDLE_VERSION + 1);

        let error = parse_verified_community_list(&bundle.to_string(), asset_body)
            .expect_err("unknown version must be rejected");

        assert!(error.contains("Unsupported community bundle version"));
    }

    #[test]
    fn verified_community_list_rejects_unexpected_asset_name() {
        let asset_body = "[\"safe-game\"]\n";
        let mut bundle: serde_json::Value = serde_json::from_str(&bundle_for(asset_body)).unwrap();
        bundle["asset"] = serde_json::json!("other.json");

        let error = parse_verified_community_list(&bundle.to_string(), asset_body)
            .expect_err("wrong asset name must be rejected");

        assert!(error.contains("Unexpected community bundle asset"));
    }
}
