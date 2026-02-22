use std::time::{Duration, Instant};

use sysinfo::System;

/// Abstraction over system metrics for testability.
pub trait SystemMetricsSource: Send {
    fn global_cpu_usage(&mut self) -> f32;
    fn available_memory(&mut self) -> u64;
}

/// Real system source backed by `sysinfo::System`.
pub struct SysinfoSource {
    system: System,
}

impl SysinfoSource {
    pub fn new() -> Self {
        Self {
            // optimized: reuses internal buffers for subsequent refreshes
            system: System::new(),
        }
    }
}

impl Default for SysinfoSource {
    fn default() -> Self {
        Self::new()
    }
}

impl SystemMetricsSource for SysinfoSource {
    fn global_cpu_usage(&mut self) -> f32 {
        self.system.refresh_cpu_all();
        self.system.global_cpu_usage()
    }

    fn available_memory(&mut self) -> u64 {
        self.system.refresh_memory();
        self.system.available_memory()
    }
}

/// Configuration for idle detection thresholds.
pub struct IdleConfig {
    /// CPU usage percentage below which the system is considered idle.
    pub cpu_threshold_percent: f32,
    /// How long CPU must stay below threshold before idle is confirmed.
    pub idle_duration: Duration,
}

impl Default for IdleConfig {
    fn default() -> Self {
        Self {
            cpu_threshold_percent: 10.0,
            idle_duration: Duration::from_secs(120), // 2 minutes
        }
    }
}

/// Monitors system metrics to determine whether the machine is idle.
pub struct IdleDetector {
    metrics_source: Box<dyn SystemMetricsSource>,
    config: IdleConfig,
    idle_since: Option<Instant>,
}

impl IdleDetector {
    pub fn new(config: IdleConfig) -> Self {
        Self {
            metrics_source: Box::new(SysinfoSource::new()),
            config,
            idle_since: None,
        }
    }

    pub fn with_metrics_source(
        config: IdleConfig,
        metrics_source: Box<dyn SystemMetricsSource>,
    ) -> Self {
        Self {
            metrics_source,
            config,
            idle_since: None,
        }
    }

    pub fn is_idle(&mut self) -> bool {
        let cpu_usage = self.metrics_source.global_cpu_usage();

        if cpu_usage < self.config.cpu_threshold_percent {
            let now = Instant::now();
            let idle_start = self.idle_since.get_or_insert(now);
            now.duration_since(*idle_start) >= self.config.idle_duration
        } else {
            self.idle_since = None;
            false
        }
    }

    pub fn cpu_usage(&mut self) -> f32 {
        self.metrics_source.global_cpu_usage()
    }

    pub fn available_memory(&mut self) -> u64 {
        self.metrics_source.available_memory()
    }

    pub fn config(&self) -> &IdleConfig {
        &self.config
    }

    pub fn update_config(&mut self, config: IdleConfig) {
        self.config = config;
        self.idle_since = None;
    }
}

impl Default for IdleDetector {
    fn default() -> Self {
        Self::new(IdleConfig::default())
    }
}

#[cfg(test)]
pub struct MockMetricsSource {
    pub cpu: f32,
    pub memory: u64,
}

#[cfg(test)]
impl SystemMetricsSource for MockMetricsSource {
    fn global_cpu_usage(&mut self) -> f32 {
        self.cpu
    }

    fn available_memory(&mut self) -> u64 {
        self.memory
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_has_expected_values() {
        let config = IdleConfig::default();
        assert!((config.cpu_threshold_percent - 10.0).abs() < f32::EPSILON);
        assert_eq!(config.idle_duration, Duration::from_secs(120));
    }

    #[test]
    fn idle_after_configured_duration() {
        // threshold=100% means any CPU reading will be below threshold
        let config = IdleConfig {
            cpu_threshold_percent: 100.0,
            idle_duration: Duration::from_millis(50),
        };
        let mock = MockMetricsSource {
            cpu: 5.0,
            memory: 1024,
        };
        let mut detector = IdleDetector::with_metrics_source(config, Box::new(mock));

        // First call sets the idle_since timestamp
        let _ = detector.is_idle();
        std::thread::sleep(Duration::from_millis(60));
        assert!(detector.is_idle());
    }

    #[test]
    fn high_cpu_resets_idle_timer() {
        // threshold=0% means any nonzero CPU reading will be above threshold
        let config = IdleConfig {
            cpu_threshold_percent: 0.0,
            idle_duration: Duration::from_millis(1),
        };
        let mock = MockMetricsSource {
            cpu: 50.0,
            memory: 1024,
        };
        let mut detector = IdleDetector::with_metrics_source(config, Box::new(mock));

        std::thread::sleep(Duration::from_millis(5));
        assert!(!detector.is_idle());
    }

    #[test]
    fn cpu_usage_returns_reasonable_value() {
        let mut detector = IdleDetector::default();
        let usage = detector.cpu_usage();
        assert!((0.0..=100.0).contains(&usage));
    }

    #[test]
    fn available_memory_returns_value() {
        let mut detector = IdleDetector::default();
        let memory = detector.available_memory();
        assert!(memory > 0);
    }

    #[test]
    fn update_config_resets_idle_timer() {
        let config = IdleConfig {
            cpu_threshold_percent: 100.0,
            idle_duration: Duration::from_millis(1),
        };
        let mock = MockMetricsSource {
            cpu: 5.0,
            memory: 1024,
        };
        let mut detector = IdleDetector::with_metrics_source(config, Box::new(mock));

        // Prime idle state
        let _ = detector.is_idle();
        std::thread::sleep(Duration::from_millis(5));
        assert!(detector.is_idle());

        // Update config should reset idle timer
        detector.update_config(IdleConfig {
            cpu_threshold_percent: 100.0,
            idle_duration: Duration::from_secs(999),
        });
        assert!(!detector.is_idle());
    }
}

#[cfg(test)]
mod property_tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        /// P9: High CPU -> not idle
        #[test]
        fn high_cpu_never_idle(cpu in 10.0f32..100.0) {
            let config = IdleConfig {
                cpu_threshold_percent: 10.0,
                idle_duration: Duration::from_millis(1),
            };
            let mock = MockMetricsSource { cpu, memory: 1024 };
            let mut detector = IdleDetector::with_metrics_source(config, Box::new(mock));
            std::thread::sleep(Duration::from_millis(5));
            prop_assert!(!detector.is_idle());
        }

        /// P13: Transient dips don't trigger idle.
        /// Alternate high/low readings shorter than idle_duration.
        #[test]
        fn transient_dips_do_not_trigger_idle(
            high_cpu in 50.0f32..100.0,
            low_cpu in 0.0f32..5.0,
            cycles in 1usize..5,
        ) {
            let config = IdleConfig {
                cpu_threshold_percent: 10.0,
                idle_duration: Duration::from_millis(200),
            };
            // Use a changeable mock
            struct AlternatingCpu {
                high: f32,
                low: f32,
                step: usize,
            }
            impl SystemMetricsSource for AlternatingCpu {
                fn global_cpu_usage(&mut self) -> f32 {
                    self.step += 1;
                    if self.step.is_multiple_of(2) { self.high } else { self.low }
                }
                fn available_memory(&mut self) -> u64 { 1024 }
            }
            let mock = AlternatingCpu { high: high_cpu, low: low_cpu, step: 0 };
            let mut detector = IdleDetector::with_metrics_source(config, Box::new(mock));

            for _ in 0..cycles {
                // Each cycle is too short for idle_duration (200ms)
                std::thread::sleep(Duration::from_millis(5));
                prop_assert!(!detector.is_idle());
            }
        }
    }
}
