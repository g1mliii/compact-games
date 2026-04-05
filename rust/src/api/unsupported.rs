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

    const URL: &str = unsupported_games::DEFAULT_COMMUNITY_LIST_ENDPOINT;
    const TIMEOUT_SECS: u64 = 15;
    const MAX_REDIRECTS: usize = 5;

    let agent = ureq::Agent::new_with_config(
        ureq::config::Config::builder()
            .timeout_global(Some(std::time::Duration::from_secs(TIMEOUT_SECS)))
            .build(),
    );

    // GitHub's `releases/latest/download/...` uses redirects; handle them explicitly
    // so we don't depend on client default redirect policy.
    let mut next_url = URL.to_string();
    let mut body: Option<String> = None;
    for _ in 0..=MAX_REDIRECTS {
        let mut response = agent
            .get(&next_url)
            .header("User-Agent", "CompactGames-Community-List/1")
            .call()
            .map_err(|e| format!("HTTP request failed: {e}"))?;

        let status = response.status();
        let code = status.as_u16();
        if (300..400).contains(&code) {
            let location = response
                .headers()
                .get("location")
                .and_then(|value| value.to_str().ok())
                .ok_or_else(|| format!("Redirect ({code}) missing Location header"))?;
            next_url = location.to_string();
            continue;
        }
        if code != 200 {
            return Err(format!("Unexpected HTTP status: {code}"));
        }

        body = Some(
            response
                .body_mut()
                .read_to_string()
                .map_err(|e| format!("Failed to read response body: {e}"))?,
        );
        break;
    }
    let body = body.ok_or_else(|| "Too many redirects".to_string())?;

    let games: Vec<String> =
        serde_json::from_str(&body).map_err(|e| format!("Invalid JSON: {e}"))?;
    let count = games.len() as u32;

    unsupported_games::update_community_list(games)?;
    unsupported_games::mark_community_list_fetched()?;
    Ok(count)
}
