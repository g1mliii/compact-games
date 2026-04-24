use std::path::Path;

use rayon::iter::ParallelBridge;
use rayon::prelude::*;

use super::estimation;
use super::{
    CompressionEngine, CompressionError, CompressionEstimate, CompressionEstimateSource,
    EstimateCandidate, EstimateTotals, ManifestFile, MIN_COMPRESSIBLE_SIZE,
    USE_ADAPTIVE_ESTIMATION,
};
use crate::compression::community_db::{self, CommunityLookup, GameLookupContext};

#[derive(Debug, Clone, Copy)]
pub struct EstimateGameContext<'a> {
    pub game_name: Option<&'a str>,
    pub steam_app_id: Option<u32>,
    pub known_size_bytes: Option<u64>,
}

#[derive(Debug, Clone, Copy, Default)]
struct AdaptiveFactors {
    correction_factor: f64,
    confidence: f64,
}

impl AdaptiveFactors {
    fn neutral() -> Self {
        Self {
            correction_factor: 1.0,
            confidence: 0.0,
        }
    }

    fn applied(self) -> bool {
        adaptive_applied(self.correction_factor, self.confidence)
    }
}

enum CommunityEstimateLookup {
    Hit(CompressionEstimate),
    Pending,
    Miss,
}

impl CompressionEngine {
    pub fn estimate_folder_savings(
        &self,
        folder: &Path,
    ) -> Result<CompressionEstimate, CompressionError> {
        self.validate_path(folder)?;
        let factors = self.compute_adaptive_factors(folder);
        self.estimate_folder_savings_with_factors(folder, factors, false)
    }

    pub fn estimate_folder_savings_with_context(
        &self,
        folder: &Path,
        context: EstimateGameContext<'_>,
    ) -> Result<CompressionEstimate, CompressionError> {
        self.validate_path(folder)?;
        let factors = self.compute_adaptive_factors(folder);
        let mut community_lookup_pending = false;
        if USE_ADAPTIVE_ESTIMATION {
            match self.community_estimate(context, context.known_size_bytes, folder, factors) {
                CommunityEstimateLookup::Hit(estimate) => return Ok(estimate),
                CommunityEstimateLookup::Pending => community_lookup_pending = true,
                CommunityEstimateLookup::Miss => {}
            }
        }
        self.estimate_folder_savings_with_factors(folder, factors, community_lookup_pending)
    }

    pub fn estimate_folder_savings_with_manifest(
        &self,
        folder: &Path,
        file_manifest: &[ManifestFile],
    ) -> Result<CompressionEstimate, CompressionError> {
        self.validate_path(folder)?;
        let factors = self.compute_adaptive_factors(folder);
        self.estimate_folder_savings_with_manifest_and_factors(file_manifest, factors, false)
    }

    pub fn estimate_folder_savings_with_manifest_and_context(
        &self,
        folder: &Path,
        file_manifest: &[ManifestFile],
        context: EstimateGameContext<'_>,
    ) -> Result<CompressionEstimate, CompressionError> {
        self.validate_path(folder)?;
        let factors = self.compute_adaptive_factors(folder);
        let mut community_lookup_pending = false;
        if USE_ADAPTIVE_ESTIMATION {
            let manifest_size = context
                .known_size_bytes
                .or_else(|| manifest_total_size(file_manifest));
            match self.community_estimate(context, manifest_size, folder, factors) {
                CommunityEstimateLookup::Hit(estimate) => return Ok(estimate),
                CommunityEstimateLookup::Pending => community_lookup_pending = true,
                CommunityEstimateLookup::Miss => {}
            }
        }
        self.estimate_folder_savings_with_manifest_and_factors(
            file_manifest,
            factors,
            community_lookup_pending,
        )
    }

    fn compute_adaptive_factors(&self, folder: &Path) -> AdaptiveFactors {
        if !USE_ADAPTIVE_ESTIMATION {
            return AdaptiveFactors::neutral();
        }
        let history = crate::compression::history::get_historical_stats();
        let estimator =
            crate::compression::history::adaptive::AdaptiveEstimator::from_history(history);
        let (correction_factor, confidence) =
            estimator.get_correction_factor_for_game(self.algorithm, folder);
        AdaptiveFactors {
            correction_factor,
            confidence,
        }
    }

    fn estimate_folder_savings_with_factors(
        &self,
        folder: &Path,
        factors: AdaptiveFactors,
        community_lookup_pending: bool,
    ) -> Result<CompressionEstimate, CompressionError> {
        let algorithm_scale_num = estimation::algorithm_scale_num(self.algorithm);
        let totals = self.estimate_totals_parallel(folder, |path, file_size| {
            saved_for_file_with_factors(
                self.algorithm,
                algorithm_scale_num,
                path,
                file_size,
                factors,
            )
        })?;
        Ok(heuristic_estimate(
            totals,
            factors,
            community_lookup_pending,
        ))
    }

    fn estimate_folder_savings_with_manifest_and_factors(
        &self,
        file_manifest: &[ManifestFile],
        factors: AdaptiveFactors,
        community_lookup_pending: bool,
    ) -> Result<CompressionEstimate, CompressionError> {
        let algorithm_scale_num = estimation::algorithm_scale_num(self.algorithm);
        let totals = self.estimate_totals_from_manifest(file_manifest, |path, file_size| {
            saved_for_file_with_factors(
                self.algorithm,
                algorithm_scale_num,
                path,
                file_size,
                factors,
            )
        })?;
        Ok(heuristic_estimate(
            totals,
            factors,
            community_lookup_pending,
        ))
    }

    fn community_estimate(
        &self,
        context: EstimateGameContext<'_>,
        size_bytes: Option<u64>,
        folder: &Path,
        factors: AdaptiveFactors,
    ) -> CommunityEstimateLookup {
        let Some(size_bytes) = size_bytes else {
            return CommunityEstimateLookup::Miss;
        };
        if size_bytes == 0 {
            return CommunityEstimateLookup::Miss;
        }

        let community = match community_db::lookup(
            GameLookupContext {
                steam_app_id: context.steam_app_id,
                game_name: context.game_name,
                game_path: folder,
            },
            self.algorithm,
        ) {
            CommunityLookup::Hit(community) => community,
            CommunityLookup::Pending => return CommunityEstimateLookup::Pending,
            CommunityLookup::Miss => return CommunityEstimateLookup::Miss,
        };

        let base_saved = (size_bytes as f64 * community.saved_ratio) as u64;
        let estimated_saved_bytes = Self::apply_adaptive_adjustment(
            base_saved,
            factors.correction_factor,
            factors.confidence,
        );

        CommunityEstimateLookup::Hit(CompressionEstimate {
            scanned_files: 0,
            sampled_bytes: size_bytes,
            estimated_saved_bytes,
            executable_candidate_path: None,
            base_source: CompressionEstimateSource::CommunityDb,
            adaptive_applied: factors.applied(),
            community_samples: Some(community.samples),
            community_lookup_pending: false,
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
        let totals = Self::file_iter(folder)?
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

fn saved_for_file_with_factors(
    _algorithm: super::CompressionAlgorithm,
    algorithm_scale_num: u64,
    path: &Path,
    file_size: u64,
    factors: AdaptiveFactors,
) -> u64 {
    let (ratio_num, ratio_den) = estimation::compression_ratio_parts(path);
    let default_saved = file_size
        .saturating_mul(ratio_num)
        .saturating_mul(algorithm_scale_num)
        / ratio_den.saturating_mul(100);
    if !USE_ADAPTIVE_ESTIMATION {
        return default_saved;
    }
    CompressionEngine::apply_adaptive_adjustment(
        default_saved,
        factors.correction_factor,
        factors.confidence,
    )
}

fn heuristic_estimate(
    totals: EstimateTotals,
    factors: AdaptiveFactors,
    community_lookup_pending: bool,
) -> CompressionEstimate {
    CompressionEstimate {
        scanned_files: totals.scanned_files,
        sampled_bytes: totals.sampled_bytes,
        estimated_saved_bytes: totals.estimated_saved_bytes,
        executable_candidate_path: totals.executable_candidate.map(|c| c.path),
        base_source: CompressionEstimateSource::Heuristic,
        adaptive_applied: factors.applied(),
        community_samples: None,
        community_lookup_pending,
    }
}

fn manifest_total_size(file_manifest: &[ManifestFile]) -> Option<u64> {
    let mut total = 0_u64;
    let mut known = 0_usize;
    for file in file_manifest {
        if let Some(size) = file.logical_size_hint {
            total = total.saturating_add(size);
            known += 1;
        }
    }
    (known > 0).then_some(total)
}

fn adaptive_applied(correction_factor: f64, confidence: f64) -> bool {
    (correction_factor - 1.0).abs() > f64::EPSILON
        && (correction_factor < 1.0 || confidence > f64::EPSILON)
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
