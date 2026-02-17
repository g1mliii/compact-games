use std::path::{Path, PathBuf};

use rayon::iter::ParallelBridge;
use rayon::prelude::*;

use super::estimation;
use super::{
    CompressionEngine, CompressionError, CompressionEstimate, EstimateTotals,
    MIN_COMPRESSIBLE_SIZE, USE_ADAPTIVE_ESTIMATION,
};

impl CompressionEngine {
    pub fn estimate_folder_savings(
        &self,
        folder: &Path,
    ) -> Result<CompressionEstimate, CompressionError> {
        self.validate_path(folder)?;
        if !USE_ADAPTIVE_ESTIMATION {
            return self.estimate_folder_savings_legacy(folder);
        }

        let history = crate::compression::history::get_historical_stats();
        let estimator =
            crate::compression::history::adaptive::AdaptiveEstimator::from_history(history);
        let (correction_factor, confidence) =
            estimator.get_correction_factor_for_game(self.algorithm, folder);
        let algorithm_scale_num = estimation::algorithm_scale_num(self.algorithm);

        let totals = self.estimate_totals_parallel(folder, |path, file_size| {
            let (ratio_num, ratio_den) = estimation::compression_ratio_parts(path);
            let default_saved = file_size
                .saturating_mul(ratio_num)
                .saturating_mul(algorithm_scale_num)
                / ratio_den.saturating_mul(100);
            Self::apply_adaptive_adjustment(default_saved, correction_factor, confidence)
        })?;

        Ok(CompressionEstimate {
            scanned_files: totals.scanned_files,
            sampled_bytes: totals.sampled_bytes,
            estimated_saved_bytes: totals.estimated_saved_bytes,
        })
    }

    pub fn estimate_folder_savings_with_manifest(
        &self,
        folder: &Path,
        file_manifest: &[PathBuf],
    ) -> Result<CompressionEstimate, CompressionError> {
        self.validate_path(folder)?;
        if !USE_ADAPTIVE_ESTIMATION {
            return self.estimate_folder_savings_legacy_with_manifest(file_manifest);
        }

        let history = crate::compression::history::get_historical_stats();
        let estimator =
            crate::compression::history::adaptive::AdaptiveEstimator::from_history(history);
        let (correction_factor, confidence) =
            estimator.get_correction_factor_for_game(self.algorithm, folder);
        let algorithm_scale_num = estimation::algorithm_scale_num(self.algorithm);

        let totals = self.estimate_totals_from_manifest(file_manifest, |path, file_size| {
            let (ratio_num, ratio_den) = estimation::compression_ratio_parts(path);
            let default_saved = file_size
                .saturating_mul(ratio_num)
                .saturating_mul(algorithm_scale_num)
                / ratio_den.saturating_mul(100);
            Self::apply_adaptive_adjustment(default_saved, correction_factor, confidence)
        })?;

        Ok(CompressionEstimate {
            scanned_files: totals.scanned_files,
            sampled_bytes: totals.sampled_bytes,
            estimated_saved_bytes: totals.estimated_saved_bytes,
        })
    }

    fn estimate_folder_savings_legacy(
        &self,
        folder: &Path,
    ) -> Result<CompressionEstimate, CompressionError> {
        let algorithm_scale_num = estimation::algorithm_scale_num(self.algorithm);
        let totals = self.estimate_totals_parallel(folder, |path, file_size| {
            let (ratio_num, ratio_den) = estimation::compression_ratio_parts(path);
            file_size
                .saturating_mul(ratio_num)
                .saturating_mul(algorithm_scale_num)
                / ratio_den.saturating_mul(100)
        })?;

        Ok(CompressionEstimate {
            scanned_files: totals.scanned_files,
            sampled_bytes: totals.sampled_bytes,
            estimated_saved_bytes: totals.estimated_saved_bytes,
        })
    }

    fn estimate_folder_savings_legacy_with_manifest(
        &self,
        file_manifest: &[PathBuf],
    ) -> Result<CompressionEstimate, CompressionError> {
        let algorithm_scale_num = estimation::algorithm_scale_num(self.algorithm);
        let totals = self.estimate_totals_from_manifest(file_manifest, |path, file_size| {
            let (ratio_num, ratio_den) = estimation::compression_ratio_parts(path);
            file_size
                .saturating_mul(ratio_num)
                .saturating_mul(algorithm_scale_num)
                / ratio_den.saturating_mul(100)
        })?;

        Ok(CompressionEstimate {
            scanned_files: totals.scanned_files,
            sampled_bytes: totals.sampled_bytes,
            estimated_saved_bytes: totals.estimated_saved_bytes,
        })
    }

    fn apply_adaptive_adjustment(
        default_saved: u64,
        correction_factor: f64,
        confidence: f64,
    ) -> u64 {
        // Asymmetric safety: apply full same-game downward correction quickly,
        // but keep blended confidence for upward corrections.
        if correction_factor < 1.0 {
            return (default_saved as f64 * correction_factor) as u64;
        }

        if confidence <= f64::EPSILON {
            return default_saved;
        }

        let adaptive_saved = (default_saved as f64 * correction_factor) as u64;
        ((default_saved as f64 * (1.0 - confidence)) + (adaptive_saved as f64 * confidence)) as u64
    }

    fn estimate_totals_parallel<F>(
        &self,
        folder: &Path,
        saved_for_file: F,
    ) -> Result<EstimateTotals, CompressionError>
    where
        F: Fn(&Path, u64) -> u64 + Sync,
    {
        let totals = Self::file_iter(folder)
            .par_bridge()
            .map(|entry| {
                if self.cancel_token.is_cancelled() {
                    return EstimateTotals {
                        saw_cancel: true,
                        ..EstimateTotals::default()
                    };
                }

                let metadata = match entry.metadata() {
                    Ok(metadata) => metadata,
                    Err(_) => return EstimateTotals::default(),
                };
                let file_size = metadata.len();

                let mut totals = EstimateTotals {
                    scanned_files: 1,
                    sampled_bytes: file_size,
                    ..EstimateTotals::default()
                };

                if file_size < MIN_COMPRESSIBLE_SIZE {
                    return totals;
                }

                totals.estimated_saved_bytes = saved_for_file(entry.path(), file_size);
                totals
            })
            .reduce(EstimateTotals::default, EstimateTotals::merge);

        if totals.saw_cancel || self.cancel_token.is_cancelled() {
            return Err(CompressionError::Cancelled);
        }

        Ok(totals)
    }

    fn estimate_totals_from_manifest<F>(
        &self,
        file_manifest: &[PathBuf],
        saved_for_file: F,
    ) -> Result<EstimateTotals, CompressionError>
    where
        F: Fn(&Path, u64) -> u64 + Sync,
    {
        let totals = file_manifest
            .par_iter()
            .map(|path| {
                if self.cancel_token.is_cancelled() {
                    return EstimateTotals {
                        saw_cancel: true,
                        ..EstimateTotals::default()
                    };
                }

                let metadata = match std::fs::metadata(path) {
                    Ok(metadata) => metadata,
                    Err(_) => return EstimateTotals::default(),
                };
                let file_size = metadata.len();

                let mut totals = EstimateTotals {
                    scanned_files: 1,
                    sampled_bytes: file_size,
                    ..EstimateTotals::default()
                };

                if file_size < MIN_COMPRESSIBLE_SIZE {
                    return totals;
                }

                totals.estimated_saved_bytes = saved_for_file(path, file_size);
                totals
            })
            .reduce(EstimateTotals::default, EstimateTotals::merge);

        if totals.saw_cancel || self.cancel_token.is_cancelled() {
            return Err(CompressionError::Cancelled);
        }

        Ok(totals)
    }
}
