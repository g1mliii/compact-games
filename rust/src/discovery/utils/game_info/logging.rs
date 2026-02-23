use std::path::Path;

use crate::discovery::platform::{DiscoveryScanMode, Platform};

pub(super) fn log_candidate_decision(
    decision: &str,
    platform: Platform,
    name: &str,
    stats_path: &Path,
    mode: DiscoveryScanMode,
    detail: &str,
) {
    log::debug!(
        "discovery[{decision}] platform={} mode={} name=\"{}\" path={} reason={}",
        platform,
        mode_label(mode),
        name,
        stats_path.display(),
        detail
    );
}

fn mode_label(mode: DiscoveryScanMode) -> &'static str {
    match mode {
        DiscoveryScanMode::Quick => "quick",
        DiscoveryScanMode::Full => "full",
    }
}
