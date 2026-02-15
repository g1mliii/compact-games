use std::time::{Duration, Instant};

use sysinfo::System;

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
    system: System,
    config: IdleConfig,
    idle_since: Option<Instant>,
}

impl IdleDetector {
    pub fn new(config: IdleConfig) -> Self {
        Self {
            system: System::new(),
            config,
            idle_since: None,
        }
    }

    pub fn is_idle(&mut self) -> bool {
        self.system.refresh_cpu_all();

        let cpu_usage = self.system.global_cpu_usage();

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
        self.system.refresh_cpu_all();
        self.system.global_cpu_usage()
    }

    pub fn available_memory(&mut self) -> u64 {
        self.system.refresh_memory();
        self.system.available_memory()
    }
}

impl Default for IdleDetector {
    fn default() -> Self {
        Self::new(IdleConfig::default())
    }
}
