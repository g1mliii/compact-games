use std::path::Path;

use crate::discovery::storage::{storage_class_for_path, StorageClass};

const EXPERT_OVERRIDE_MAX_THREADS: usize = 16;

/// Controls how the compression engine competes for the disk.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ThreadPolicy {
    pub io_parallelism: usize,
    pub is_background: bool,
    /// Run the worker threads at Windows background I/O priority.
    ///
    /// Separate from [`is_background`] because the two answer different
    /// questions: that one is "should this job be quiet about CPU and thread
    /// count", this one is "may this job outrank foreground processes at the
    /// disk". Thread count alone does not bound disk queue depth — a few
    /// threads issuing large writes will still starve the machine — so any job
    /// that rewrites whole files needs this regardless of who started it.
    pub low_io_priority: bool,
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

/// Like [`compute_thread_policy`], but for work that rewrites whole files.
///
/// Decompression restores every file to its full logical size, so it writes
/// more than it reads and does so across every worker at once. Left at normal
/// priority that saturates the disk queue and the whole machine stalls behind
/// it, so it always runs at background I/O priority even when the user started
/// it, and gets a lower thread ceiling on top.
pub fn compute_rewrite_thread_policy(
    game_path: &Path,
    is_background: bool,
    cpu_usage_percent: Option<f32>,
    io_parallelism_override: Option<usize>,
) -> ThreadPolicy {
    let base = compute_thread_policy(
        game_path,
        is_background,
        cpu_usage_percent,
        io_parallelism_override,
    );
    ThreadPolicy {
        // An explicit override is the user telling us they know better.
        io_parallelism: match io_parallelism_override {
            Some(_) => base.io_parallelism,
            None => base.io_parallelism.min(MAX_REWRITE_PARALLELISM),
        },
        low_io_priority: true,
        ..base
    }
}

/// Ceiling for write-amplifying work. Past a small number of concurrent write
/// streams the disk is the bottleneck anyway, so extra threads buy queue depth
/// rather than throughput.
const MAX_REWRITE_PARALLELISM: usize = 4;

fn compute_thread_policy_for_storage(
    storage: StorageClass,
    is_background: bool,
    cpu_usage_percent: Option<f32>,
    io_parallelism_override: Option<usize>,
) -> ThreadPolicy {
    compute_thread_policy_for_storage_and_cpu_count(
        storage,
        is_background,
        cpu_usage_percent,
        io_parallelism_override,
        num_cpus::get(),
    )
}

fn compute_thread_policy_for_storage_and_cpu_count(
    storage: StorageClass,
    is_background: bool,
    cpu_usage_percent: Option<f32>,
    io_parallelism_override: Option<usize>,
    logical_cpu_count: usize,
) -> ThreadPolicy {
    let storage_base = match storage {
        StorageClass::Hdd => 2,
        StorageClass::Ssd | StorageClass::Unknown => logical_cpu_count.clamp(1, 8),
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
        // Background jobs must never outrank whatever the user is doing.
        low_io_priority: is_background,
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
    fn low_cpu_background_ssd_keeps_four_workers_on_eight_core_host() {
        let policy = compute_thread_policy_for_storage_and_cpu_count(
            StorageClass::Ssd,
            true,
            Some(10.0),
            None,
            8,
        );

        assert_eq!(policy.io_parallelism, 4);
    }

    #[test]
    fn bogus_high_cpu_sample_would_collapse_background_ssd_to_one_worker() {
        let policy = compute_thread_policy_for_storage_and_cpu_count(
            StorageClass::Ssd,
            true,
            Some(100.0),
            None,
            8,
        );

        assert_eq!(policy.io_parallelism, 1);
    }

    #[test]
    fn foreground_work_keeps_normal_io_priority() {
        let policy = policy_for_storage(StorageClass::Ssd, false, None, None);
        assert!(!policy.low_io_priority);
    }

    #[test]
    fn background_work_drops_to_low_io_priority() {
        // Thread count alone does not bound disk queue depth, so a background
        // job must also yield the disk to whatever the user is doing.
        let policy = policy_for_storage(StorageClass::Ssd, true, None, None);
        assert!(policy.low_io_priority);
    }

    #[test]
    fn rewrite_work_yields_the_disk_even_in_the_foreground() {
        let path = Path::new(r"C:\Games\example");
        let policy = compute_rewrite_thread_policy(path, false, None, None);
        assert!(policy.low_io_priority);
        assert!(!policy.is_background);
    }

    #[test]
    fn rewrite_work_caps_concurrent_write_streams() {
        let path = Path::new(r"C:\Games\example");
        let foreground = compute_thread_policy(path, false, None, None);
        let rewrite = compute_rewrite_thread_policy(path, false, None, None);

        assert!(rewrite.io_parallelism <= MAX_REWRITE_PARALLELISM);
        assert!(rewrite.io_parallelism <= foreground.io_parallelism);
        assert!(rewrite.io_parallelism >= 1);
    }

    #[test]
    fn rewrite_work_still_honours_an_explicit_override() {
        // The cap is a default, not a ceiling the user cannot raise.
        let policy = compute_rewrite_thread_policy(
            Path::new(r"C:\Games\example"),
            false,
            None,
            Some(MAX_REWRITE_PARALLELISM + 4),
        );
        assert_eq!(policy.io_parallelism, MAX_REWRITE_PARALLELISM + 4);
        assert!(policy.low_io_priority);
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
