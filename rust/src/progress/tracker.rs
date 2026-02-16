use std::sync::Arc;
use std::time::Duration;

use serde::{Deserialize, Serialize};

/// Real-time progress data for an active compression operation.
///
/// Sent to the Flutter UI via crossbeam channel / FRB stream.
/// Updates are batched to avoid flooding the UI (max every 100ms).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CompressionProgress {
    pub game_name: Arc<str>,
    pub files_total: u64,
    pub files_processed: u64,
    pub bytes_original: u64,
    pub bytes_compressed: u64,
    pub bytes_saved: u64,
    pub estimated_time_remaining: Option<Duration>,
    pub is_complete: bool,
}

impl CompressionProgress {
    /// Progress as a fraction between 0.0 and 1.0.
    pub fn fraction(&self) -> f64 {
        if self.files_total == 0 {
            return 0.0;
        }
        self.files_processed as f64 / self.files_total as f64
    }

    /// Progress as a percentage (0 - 100).
    pub fn percent(&self) -> u8 {
        (self.fraction() * 100.0).min(100.0) as u8
    }

    /// Throughput in bytes per second, or 0 if not enough data.
    pub fn throughput_bps(&self, elapsed: Duration) -> u64 {
        if elapsed.as_secs() == 0 {
            return 0;
        }
        self.bytes_original / elapsed.as_secs()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn progress_fraction_zero_when_no_files() {
        let p = CompressionProgress {
            game_name: Arc::from(""),
            files_total: 0,
            files_processed: 0,
            bytes_original: 0,
            bytes_compressed: 0,
            bytes_saved: 0,
            estimated_time_remaining: None,
            is_complete: false,
        };
        assert_eq!(p.fraction(), 0.0);
        assert_eq!(p.percent(), 0);
    }

    #[test]
    fn progress_fraction_halfway() {
        let p = CompressionProgress {
            game_name: Arc::from("Test"),
            files_total: 100,
            files_processed: 50,
            bytes_original: 1000,
            bytes_compressed: 600,
            bytes_saved: 400,
            estimated_time_remaining: Some(Duration::from_secs(30)),
            is_complete: false,
        };
        assert!((p.fraction() - 0.5).abs() < f64::EPSILON);
        assert_eq!(p.percent(), 50);
    }
}
