use std::path::Path;

use rayon::iter::ParallelBridge;
use rayon::prelude::*;

use super::estimation;
use super::{
    CompressionEngine, CompressionError, CompressionEstimate, EstimateCandidate, EstimateTotals,
    ManifestFile, MIN_COMPRESSIBLE_SIZE, USE_ADAPTIVE_ESTIMATION,
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
            artwork_candidate_path: totals.artwork_candidate.map(|c| c.path),
            executable_candidate_path: totals.executable_candidate.map(|c| c.path),
        })
    }

    pub fn estimate_folder_savings_with_manifest(
        &self,
        folder: &Path,
        file_manifest: &[ManifestFile],
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
            artwork_candidate_path: totals.artwork_candidate.map(|c| c.path),
            executable_candidate_path: totals.executable_candidate.map(|c| c.path),
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
            artwork_candidate_path: totals.artwork_candidate.map(|c| c.path),
            executable_candidate_path: totals.executable_candidate.map(|c| c.path),
        })
    }

    fn estimate_folder_savings_legacy_with_manifest(
        &self,
        file_manifest: &[ManifestFile],
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
            artwork_candidate_path: totals.artwork_candidate.map(|c| c.path),
            executable_candidate_path: totals.executable_candidate.map(|c| c.path),
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
                let path = entry.path();

                let mut totals = EstimateTotals {
                    scanned_files: 1,
                    sampled_bytes: file_size,
                    ..EstimateTotals::default()
                };
                if let Some(score) = artwork_score(path) {
                    totals.artwork_candidate = Some(EstimateCandidate {
                        score,
                        path: path.to_path_buf(),
                        path_len: path.as_os_str().len(),
                    });
                }
                if let Some(score) = executable_score(path, file_size) {
                    totals.executable_candidate = Some(EstimateCandidate {
                        score,
                        path: path.to_path_buf(),
                        path_len: path.as_os_str().len(),
                    });
                }

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

    fn estimate_totals_from_manifest<F>(
        &self,
        file_manifest: &[ManifestFile],
        saved_for_file: F,
    ) -> Result<EstimateTotals, CompressionError>
    where
        F: Fn(&Path, u64) -> u64 + Sync,
    {
        let totals = file_manifest
            .par_iter()
            .map(|manifest_file| {
                if self.cancel_token.is_cancelled() {
                    return EstimateTotals {
                        saw_cancel: true,
                        ..EstimateTotals::default()
                    };
                }

                let file_size = match manifest_file.logical_size_hint {
                    Some(file_size) => file_size,
                    None => return EstimateTotals::default(),
                };
                let path = manifest_file.path.as_path();

                let mut totals = EstimateTotals {
                    scanned_files: 1,
                    sampled_bytes: file_size,
                    ..EstimateTotals::default()
                };
                if let Some(score) = artwork_score(path) {
                    totals.artwork_candidate = Some(EstimateCandidate {
                        score,
                        path: path.to_path_buf(),
                        path_len: path.as_os_str().len(),
                    });
                }
                if let Some(score) = executable_score(path, file_size) {
                    totals.executable_candidate = Some(EstimateCandidate {
                        score,
                        path: path.to_path_buf(),
                        path_len: path.as_os_str().len(),
                    });
                }

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

fn artwork_score(path: &Path) -> Option<u16> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())?;
    if !matches!(
        ext.as_str(),
        "jpg" | "jpeg" | "png" | "webp" | "bmp" | "ico"
    ) {
        return None;
    }

    let name = path
        .file_stem()
        .and_then(|s| s.to_str())
        .map(|s| s.to_ascii_lowercase())
        .unwrap_or_default();
    let mut score = 0;
    if name.contains("cover") {
        score += 45;
    }
    if name.contains("library_600x900") {
        score += 45;
    }
    if name.contains("capsule") {
        score += 40;
    }
    if name.contains("poster") {
        score += 35;
    }
    if name.contains("banner") {
        score += 28;
    }
    if name.contains("hero") {
        score += 22;
    }
    if name.contains("logo") || name.contains("icon") {
        score += 14;
    }
    if score == 0 {
        return None;
    }
    if ext == "jpg" || ext == "png" {
        score += 5;
    }
    Some(score)
}

fn executable_score(path: &Path, file_size: u64) -> Option<u16> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())?;
    if ext != "exe" {
        return None;
    }

    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .map(|n| n.to_ascii_lowercase())
        .unwrap_or_default();
    if is_non_game_executable_name(&file_name) {
        return None;
    }

    // Favor larger binaries because launch executables are often among the larger EXEs.
    let size_mb = (file_size / (1024 * 1024)).min(200);
    let size_score = u16::try_from(size_mb).unwrap_or(200);
    Some(20 + size_score)
}

fn is_non_game_executable_name(name: &str) -> bool {
    name.contains("setup")
        || name.contains("install")
        || name.contains("unins")
        || name.contains("launcher")
        || name.contains("vcredist")
        || name.contains("dxsetup")
        || name.contains("prereq")
}
