//! Unsupported games API exposed to Flutter via FRB.

use std::path::Path;

use flutter_rust_bridge::frb;

use crate::safety::unsupported_games;

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

/// Fetch the community unsupported games list from GitHub Releases and update the local cache.
/// Returns the number of games in the updated list, or an error message.
pub fn fetch_community_unsupported_list() -> Result<u32, String> {
    if !unsupported_games::should_fetch_community_list() {
        return Ok(unsupported_games::community_list_len());
    }

    const MAX_BODY_BYTES: u64 = 1024 * 1024;

    let body = crate::net::fetch_text(
        unsupported_games::DEFAULT_COMMUNITY_LIST_ENDPOINT,
        "CompactGames-Community-List/1",
        MAX_BODY_BYTES,
    )?;

    let games: Vec<String> =
        serde_json::from_str(&body).map_err(|e| format!("Invalid JSON: {e}"))?;
    let count = games.len() as u32;

    unsupported_games::update_community_list(games)?;
    unsupported_games::mark_community_list_fetched()?;
    Ok(count)
}
