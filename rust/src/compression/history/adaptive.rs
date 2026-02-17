use super::CompressionHistoryEntry;
use crate::compression::algorithm::CompressionAlgorithm;
use std::path::Path;

const MILLIS_PER_DAY: f64 = 86_400_000.0;
const DECAY_DAYS: f64 = 90.0;
const CONFIDENCE_MIN: f64 = 0.2;
const CONFIDENCE_MAX: f64 = 0.8;
const MIN_MULTIPLIER: f64 = 0.2;
const MAX_MULTIPLIER: f64 = 2.0;
const CONSERVATIVE_Z: f64 = 1.96;

/// Adaptive estimator that learns from compression history.
pub struct AdaptiveEstimator {
    history: Vec<CompressionHistoryEntry>,
    min_samples_for_confidence: usize,
}

impl AdaptiveEstimator {
    pub fn from_history(history: Vec<CompressionHistoryEntry>) -> Self {
        Self {
            history,
            min_samples_for_confidence: 10,
        }
    }

    /// Get adaptive correction factor for estimates.
    ///
    /// Returns `(multiplier, confidence)`:
    /// - `multiplier`: scales default estimate (1.0 = no change)
    /// - `confidence`: blending weight to adaptive value (0.0-0.8)
    pub fn get_correction_factor(&self, algorithm: CompressionAlgorithm) -> (f64, f64) {
        let relevant: Vec<_> = self
            .history
            .iter()
            .filter(|entry| entry.algorithm == algorithm)
            .filter(|entry| entry.estimate.estimated_saved_bytes > 0)
            .collect();

        if relevant.len() < self.min_samples_for_confidence {
            return (1.0, 0.0);
        }

        let now_ms = current_epoch_ms();
        let weighted: Vec<(f64, f64)> = relevant
            .iter()
            .map(|entry| {
                let ratio = entry.estimate_accuracy_ratio();
                let age_days = now_ms.saturating_sub(entry.timestamp_ms) as f64 / MILLIS_PER_DAY;
                let weight = (-age_days / DECAY_DAYS).exp();
                (ratio, weight)
            })
            .collect();

        let weight_sum: f64 = weighted.iter().map(|(_, weight)| *weight).sum();
        if weight_sum <= f64::EPSILON {
            return (1.0, 0.0);
        }

        let weighted_sum: f64 = weighted.iter().map(|(ratio, weight)| ratio * weight).sum();
        let mean_ratio = weighted_sum / weight_sum;

        // Use weighted variance so recent entries influence uncertainty more.
        let weighted_variance: f64 = weighted
            .iter()
            .map(|(ratio, weight)| weight * (ratio - mean_ratio).powi(2))
            .sum::<f64>()
            / weight_sum;
        let std_dev = weighted_variance.sqrt();
        let sample_count = relevant.len() as f64;
        let std_error = std_dev / sample_count.sqrt();

        // Conservative lower confidence bound to reduce over-promising.
        let conservative_multiplier =
            (mean_ratio - CONSERVATIVE_Z * std_error).clamp(MIN_MULTIPLIER, MAX_MULTIPLIER);

        // Confidence ramps from 0.2 at min samples to 0.8 by ~50 samples.
        let sample_span = (sample_count - self.min_samples_for_confidence as f64).max(0.0);
        let confidence = (CONFIDENCE_MIN
            + (sample_span / 40.0) * (CONFIDENCE_MAX - CONFIDENCE_MIN))
            .clamp(CONFIDENCE_MIN, CONFIDENCE_MAX);

        (conservative_multiplier, confidence)
    }

    /// Prefer fast, conservative per-game correction when history exists for the same path.
    /// Falls back to algorithm-level correction when game-specific history is unavailable.
    pub fn get_correction_factor_for_game(
        &self,
        algorithm: CompressionAlgorithm,
        game_path: &Path,
    ) -> (f64, f64) {
        let game_key = normalize_game_path(game_path);
        let relevant_for_game: Vec<_> = self
            .history
            .iter()
            .filter(|entry| entry.algorithm == algorithm)
            .filter(|entry| entry.estimate.estimated_saved_bytes > 0)
            .filter(|entry| normalize_game_path(Path::new(&entry.game_path)) == game_key)
            .collect();

        if relevant_for_game.is_empty() {
            return self.get_correction_factor(algorithm);
        }

        let now_ms = current_epoch_ms();
        let weighted: Vec<(f64, f64)> = relevant_for_game
            .iter()
            .map(|entry| {
                let ratio = entry.estimate_accuracy_ratio();
                let age_days = now_ms.saturating_sub(entry.timestamp_ms) as f64 / MILLIS_PER_DAY;
                let weight = (-age_days / DECAY_DAYS).exp();
                (ratio, weight)
            })
            .collect();

        let weight_sum: f64 = weighted.iter().map(|(_, weight)| *weight).sum();
        if weight_sum <= f64::EPSILON {
            return self.get_correction_factor(algorithm);
        }

        let weighted_sum: f64 = weighted.iter().map(|(ratio, weight)| ratio * weight).sum();
        let mean_ratio = weighted_sum / weight_sum;

        // Same-game fast path only lowers estimates; never raises them.
        let multiplier = mean_ratio.clamp(MIN_MULTIPLIER, 1.0);
        let sample_count = relevant_for_game.len();
        let confidence = (0.85 + 0.05 * (sample_count.saturating_sub(1)) as f64).clamp(0.85, 0.95);

        (multiplier, confidence)
    }
}

fn current_epoch_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .map(|d| d.as_millis() as u64)
        .unwrap_or_default()
}

fn normalize_game_path(path: &Path) -> String {
    let mut normalized = path.as_os_str().to_string_lossy().replace('/', "\\");
    while normalized.len() > 3 && normalized.ends_with('\\') {
        normalized.pop();
    }
    normalized.to_ascii_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compression::algorithm::CompressionAlgorithm;
    use crate::compression::history::{ActualStats, EstimateSnapshot};
    use std::path::Path;

    fn entry(
        algorithm: CompressionAlgorithm,
        ratio: f64,
        days_ago: u64,
        estimate_saved: u64,
    ) -> CompressionHistoryEntry {
        let now = current_epoch_ms();
        let actual_saved = (estimate_saved as f64 * ratio) as u64;
        CompressionHistoryEntry {
            game_path: format!("C:\\\\Games\\\\g_{days_ago}_{ratio}"),
            game_name: format!("Game {days_ago}"),
            timestamp_ms: now.saturating_sub(days_ago.saturating_mul(86_400_000)),
            estimate: EstimateSnapshot {
                scanned_files: 100,
                sampled_bytes: 10_000_000,
                estimated_saved_bytes: estimate_saved,
            },
            actual_stats: ActualStats {
                original_bytes: 10_000_000,
                compressed_bytes: 10_000_000u64.saturating_sub(actual_saved),
                actual_saved_bytes: actual_saved,
                files_processed: 100,
            },
            algorithm,
            duration_ms: 1_000,
        }
    }

    #[test]
    fn returns_default_without_minimum_samples() {
        let history = (0..9)
            .map(|i| entry(CompressionAlgorithm::Xpress8K, 1.2, i, 100_000))
            .collect();
        let estimator = AdaptiveEstimator::from_history(history);
        let (multiplier, confidence) =
            estimator.get_correction_factor(CompressionAlgorithm::Xpress8K);
        assert_eq!(multiplier, 1.0);
        assert_eq!(confidence, 0.0);
    }

    #[test]
    fn confidence_increases_with_sample_size() {
        let history_10 = (0..10)
            .map(|i| entry(CompressionAlgorithm::Xpress8K, 1.1, i, 100_000))
            .collect();
        let history_50 = (0..50)
            .map(|i| entry(CompressionAlgorithm::Xpress8K, 1.1, i, 100_000))
            .collect();

        let estimator_10 = AdaptiveEstimator::from_history(history_10);
        let estimator_50 = AdaptiveEstimator::from_history(history_50);

        let (_, confidence_10) = estimator_10.get_correction_factor(CompressionAlgorithm::Xpress8K);
        let (_, confidence_50) = estimator_50.get_correction_factor(CompressionAlgorithm::Xpress8K);

        assert!(confidence_50 > confidence_10);
        assert!(confidence_50 <= CONFIDENCE_MAX);
    }

    #[test]
    fn recent_samples_are_weighted_more_heavily() {
        let mut history = Vec::new();
        for i in 0..12 {
            history.push(entry(CompressionAlgorithm::Xpress8K, 0.8, 120 + i, 100_000));
        }
        for i in 0..12 {
            history.push(entry(CompressionAlgorithm::Xpress8K, 1.4, i, 100_000));
        }

        let estimator = AdaptiveEstimator::from_history(history);
        let (multiplier, _) = estimator.get_correction_factor(CompressionAlgorithm::Xpress8K);
        assert!(
            multiplier > 1.0,
            "recent high-ratio samples should pull multiplier above 1.0"
        );
    }

    #[test]
    fn conservative_bound_stays_below_mean_for_noisy_history() {
        let ratios = [0.7, 0.9, 1.0, 1.1, 1.4, 1.8, 0.8, 1.3, 1.6, 0.95];
        let history = ratios
            .iter()
            .enumerate()
            .map(|(i, ratio)| entry(CompressionAlgorithm::Xpress8K, *ratio, i as u64, 200_000))
            .collect::<Vec<_>>();
        let estimator = AdaptiveEstimator::from_history(history);
        let (multiplier, _) = estimator.get_correction_factor(CompressionAlgorithm::Xpress8K);

        assert!(multiplier >= MIN_MULTIPLIER);
        assert!(multiplier <= MAX_MULTIPLIER);
        assert!(
            multiplier < 1.3,
            "conservative bound should stay below noisy mean"
        );
    }

    #[test]
    fn same_game_fast_path_applies_strong_downward_correction() {
        let history = vec![CompressionHistoryEntry {
            game_path: r"C:\Games\CS2".to_string(),
            game_name: "CS2".to_string(),
            timestamp_ms: current_epoch_ms(),
            estimate: EstimateSnapshot {
                scanned_files: 100,
                sampled_bytes: 20_000_000_000,
                estimated_saved_bytes: 20_000_000_000,
            },
            actual_stats: ActualStats {
                original_bytes: 100_000_000_000,
                compressed_bytes: 95_000_000_000,
                actual_saved_bytes: 5_000_000_000, // 0.25 ratio
                files_processed: 100,
            },
            algorithm: CompressionAlgorithm::Xpress8K,
            duration_ms: 1_000,
        }];

        let estimator = AdaptiveEstimator::from_history(history);
        let (multiplier, confidence) = estimator.get_correction_factor_for_game(
            CompressionAlgorithm::Xpress8K,
            Path::new(r"C:\Games\CS2"),
        );

        assert!((MIN_MULTIPLIER..=0.26).contains(&multiplier));
        assert!(confidence >= 0.85);
    }

    #[test]
    fn same_game_fast_path_never_raises_estimate() {
        let history = vec![CompressionHistoryEntry {
            game_path: r"C:\Games\Deadlock".to_string(),
            game_name: "Deadlock".to_string(),
            timestamp_ms: current_epoch_ms(),
            estimate: EstimateSnapshot {
                scanned_files: 10,
                sampled_bytes: 1_000_000,
                estimated_saved_bytes: 100_000,
            },
            actual_stats: ActualStats {
                original_bytes: 1_000_000,
                compressed_bytes: 700_000,
                actual_saved_bytes: 300_000, // ratio 3.0
                files_processed: 10,
            },
            algorithm: CompressionAlgorithm::Xpress8K,
            duration_ms: 500,
        }];

        let estimator = AdaptiveEstimator::from_history(history);
        let (multiplier, confidence) = estimator.get_correction_factor_for_game(
            CompressionAlgorithm::Xpress8K,
            Path::new(r"C:\Games\Deadlock"),
        );

        assert_eq!(multiplier, 1.0);
        assert!(confidence >= 0.85);
    }

    #[test]
    fn same_game_fast_path_falls_back_when_no_game_history_exists() {
        let history = vec![entry(CompressionAlgorithm::Xpress8K, 0.8, 1, 100_000)];
        let estimator = AdaptiveEstimator::from_history(history);
        let (multiplier, confidence) = estimator.get_correction_factor_for_game(
            CompressionAlgorithm::Xpress8K,
            Path::new(r"C:\Games\DifferentTitle"),
        );

        assert_eq!(multiplier, 1.0);
        assert_eq!(confidence, 0.0);
    }
}
