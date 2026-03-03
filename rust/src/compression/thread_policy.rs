use std::path::Path;

use crate::discovery::storage::{storage_class_for_path, StorageClass};

const EXPERT_OVERRIDE_MAX_THREADS: usize = 16;

/// Controls how many parallel I/O threads the compression engine uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ThreadPolicy {
    pub io_parallelism: usize,
    pub is_background: bool,
}

/// Compute the optimal thread policy for a game path.
///
/// - HDD: cap at 2 threads (sequential I/O is faster than random)
/// - SSD/Unknown: up to `num_cpus` capped at 8
/// - High CPU pressure reduces foreground parallelism
/// - Background mode: halve parallelism (minimum 1)
/// - Expert override (if provided) wins after safety clamp
pub fn compute_thread_policy(
    game_path: &Path,
    is_background: bool,
    cpu_usage_percent: Option<f32>,
    io_parallelism_override: Option<usize>,
) -> ThreadPolicy {
    let storage = storage_class_for_path(game_path);
    compute_thread_policy_for_storage(
        storage,
        is_background,
        cpu_usage_percent,
        io_parallelism_override,
    )
}

fn compute_thread_policy_for_storage(
    storage: StorageClass,
    is_background: bool,
    cpu_usage_percent: Option<f32>,
    io_parallelism_override: Option<usize>,
) -> ThreadPolicy {
    let storage_base = match storage {
        StorageClass::Hdd => 2,
        StorageClass::Ssd | StorageClass::Unknown => num_cpus::get().min(8),
    };

    // When CPU is already busy, reduce foreground pressure.
    let cpu_adjusted = match cpu_usage_percent {
        Some(cpu) if cpu >= 85.0 => storage_base.min(2),
        Some(cpu) if cpu >= 65.0 => storage_base.min(4),
        _ => storage_base,
    };

    let mode_adjusted = if is_background {
        (cpu_adjusted / 2).max(1)
    } else {
        cpu_adjusted.max(1)
    };

    let io_parallelism = if let Some(expert_override) = io_parallelism_override {
        expert_override.clamp(1, EXPERT_OVERRIDE_MAX_THREADS)
    } else {
        mode_adjusted
    };

    ThreadPolicy {
        io_parallelism,
        is_background,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hdd_caps_at_two() {
        let policy = policy_for_storage(StorageClass::Hdd, false, None, None);
        assert!(policy.io_parallelism <= 2);
        assert!(policy.io_parallelism >= 1);
    }

    #[test]
    fn ssd_uses_multiple_threads() {
        let policy = policy_for_storage(StorageClass::Ssd, false, None, None);
        // At least 1 on any machine, up to min(num_cpus, 8)
        assert!(policy.io_parallelism >= 1);
        assert!(policy.io_parallelism <= 8);
    }

    #[test]
    fn unknown_defaults_to_ssd() {
        let ssd_policy = policy_for_storage(StorageClass::Ssd, false, None, None);
        let unknown_policy = policy_for_storage(StorageClass::Unknown, false, None, None);
        assert_eq!(ssd_policy.io_parallelism, unknown_policy.io_parallelism);
    }

    #[test]
    fn background_halves_parallelism() {
        let fg = policy_for_storage(StorageClass::Ssd, false, None, None);
        let bg = policy_for_storage(StorageClass::Ssd, true, None, None);
        assert_eq!(bg.io_parallelism, (fg.io_parallelism / 2).max(1));
        assert!(bg.is_background);
        assert!(!fg.is_background);
    }

    #[test]
    fn background_hdd_minimum_one() {
        let policy = policy_for_storage(StorageClass::Hdd, true, None, None);
        assert_eq!(policy.io_parallelism, 1);
    }

    #[test]
    fn high_cpu_reduces_foreground_parallelism() {
        let low_cpu = policy_for_storage(StorageClass::Ssd, false, Some(10.0), None);
        let high_cpu = policy_for_storage(StorageClass::Ssd, false, Some(90.0), None);
        assert!(high_cpu.io_parallelism <= low_cpu.io_parallelism);
        assert!(high_cpu.io_parallelism <= 2);
    }

    #[test]
    fn expert_override_wins_after_clamp() {
        let policy = policy_for_storage(StorageClass::Hdd, true, Some(95.0), Some(12));
        assert_eq!(policy.io_parallelism, 12);

        let clamped = policy_for_storage(StorageClass::Ssd, false, None, Some(99));
        assert_eq!(clamped.io_parallelism, EXPERT_OVERRIDE_MAX_THREADS);
    }

    /// Helper: compute policy from a known storage class without needing a real path.
    fn policy_for_storage(
        storage: StorageClass,
        is_background: bool,
        cpu_usage_percent: Option<f32>,
        io_parallelism_override: Option<usize>,
    ) -> ThreadPolicy {
        compute_thread_policy_for_storage(
            storage,
            is_background,
            cpu_usage_percent,
            io_parallelism_override,
        )
    }
}
