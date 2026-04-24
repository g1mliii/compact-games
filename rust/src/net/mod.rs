use std::io::Read;
use std::time::Duration;

pub mod github_release_fetcher;

pub const ALLOWED_RELEASE_URL_PREFIX: &str = "https://github.com/g1mliii/compact-games/releases/";
pub const DEFAULT_HTTP_TIMEOUT_SECS: u64 = 15;
pub const DEFAULT_HTTP_MAX_REDIRECTS: usize = 5;

pub fn is_allowed_release_url(url: &str) -> bool {
    url.starts_with(ALLOWED_RELEASE_URL_PREFIX)
}

/// Fetch a URL as text with manual redirect handling.
///
/// HTTPS-only redirect targets, body capped at `max_body_bytes`.
pub fn fetch_text(url: &str, user_agent: &str, max_body_bytes: u64) -> Result<String, String> {
    let agent = ureq::Agent::new_with_config(
        ureq::config::Config::builder()
            .timeout_global(Some(Duration::from_secs(DEFAULT_HTTP_TIMEOUT_SECS)))
            .build(),
    );

    let mut next_url = url.to_string();
    for _ in 0..=DEFAULT_HTTP_MAX_REDIRECTS {
        let response = agent
            .get(&next_url)
            .header("User-Agent", user_agent)
            .call()
            .map_err(|e| format!("HTTP request failed: {e}"))?;

        let status = response.status().as_u16();
        if (300..400).contains(&status) {
            let location = response
                .headers()
                .get("location")
                .and_then(|value| value.to_str().ok())
                .ok_or_else(|| format!("Redirect ({status}) missing Location header"))?;
            if !location.starts_with("https://") {
                return Err(format!(
                    "Refusing to follow non-HTTPS redirect to: {location}"
                ));
            }
            next_url = location.to_string();
            continue;
        }
        if status != 200 {
            return Err(format!("Unexpected HTTP status: {status}"));
        }

        let mut reader = response.into_body().into_reader().take(max_body_bytes + 1);
        let mut body = String::new();
        reader
            .read_to_string(&mut body)
            .map_err(|e| format!("Failed to read response body: {e}"))?;
        if body.len() as u64 > max_body_bytes {
            return Err("Response too large".to_string());
        }
        return Ok(body);
    }

    Err("Too many redirects".to_string())
}
