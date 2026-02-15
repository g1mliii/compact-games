//! Progress reporter that polls atomic counters on a dedicated thread
//! and sends `CompressionProgress` snapshots over a bounded channel.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crossbeam_channel::{bounded, Receiver, Sender};

use super::tracker::CompressionProgress;


pub struct EngineCounters {
    pub files_processed: Arc<AtomicU64>,
    pub files_total: Arc<AtomicU64>,
    pub bytes_original: Arc<AtomicU64>,
    pub bytes_compressed: Arc<AtomicU64>,
}


pub struct ProgressReporter {
    stop: Arc<AtomicBool>,
    handle: Option<std::thread::JoinHandle<()>>,
}

impl ProgressReporter {

    pub fn new(
        counters: EngineCounters,
        game_name: String,
    ) -> (Self, Receiver<CompressionProgress>) {
        let (tx, rx) = bounded(4);
        let stop = Arc::new(AtomicBool::new(false));
        let stop_clone = stop.clone();

        let handle = std::thread::spawn(move || {
            reporter_loop(counters, game_name, tx, stop_clone);
        });

        (
            Self {
                stop,
                handle: Some(handle),
            },
            rx,
        )
    }

    pub fn stop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
    }
}

impl Drop for ProgressReporter {
    fn drop(&mut self) {
        self.stop();
    }
}


fn reporter_loop(
    counters: EngineCounters,
    game_name: String,
    tx: Sender<CompressionProgress>,
    stop: Arc<AtomicBool>,
) {
    let mut speed_samples: VecDeque<f64> = VecDeque::with_capacity(10);
    let mut speed_sum = 0.0;
    let mut last_files: u64 = 0;
    let mut last_tick = Instant::now();

    loop {
        std::thread::sleep(Duration::from_millis(100));

        let stopping = stop.load(Ordering::Relaxed);

        let files_processed = counters.files_processed.load(Ordering::Relaxed);
        let files_total = counters.files_total.load(Ordering::Relaxed);
        let bytes_original = counters.bytes_original.load(Ordering::Relaxed);
        let bytes_compressed = counters.bytes_compressed.load(Ordering::Relaxed);
        let now = Instant::now();
        let dt = now.duration_since(last_tick).as_secs_f64();
        if dt > 0.0 {
            let files_delta = files_processed.saturating_sub(last_files);
            let speed = files_delta as f64 / dt;
            if speed_samples.len() >= 10 {
                if let Some(oldest) = speed_samples.pop_front() {
                    speed_sum -= oldest;
                }
            }
            speed_samples.push_back(speed);
            speed_sum += speed;
        }
        last_files = files_processed;
        last_tick = now;


        let avg_speed = if speed_samples.is_empty() {
            0.0
        } else {
            speed_sum / speed_samples.len() as f64
        };
        let remaining = files_total.saturating_sub(files_processed);
        let eta = if avg_speed > 0.1 {
            Some(Duration::from_secs_f64(remaining as f64 / avg_speed))
        } else {
            None
        };

        let is_complete = files_total > 0 && files_processed >= files_total;

        let progress = CompressionProgress {
            game_name: game_name.clone(),
            files_total,
            files_processed,
            bytes_original,
            bytes_compressed,
            bytes_saved: bytes_original.saturating_sub(bytes_compressed),
            estimated_time_remaining: eta,
            is_complete,
        };

        let _ = tx.try_send(progress);

        if is_complete || stopping {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reporter_stops_cleanly() {
        let counters = EngineCounters {
            files_processed: Arc::new(AtomicU64::new(0)),
            files_total: Arc::new(AtomicU64::new(10)),
            bytes_original: Arc::new(AtomicU64::new(0)),
            bytes_compressed: Arc::new(AtomicU64::new(0)),
        };
        let (mut reporter, _rx) = ProgressReporter::new(counters, "Test".into());
        reporter.stop();
        
    }

    #[test]
    fn reporter_emits_progress() {
        let counters = EngineCounters {
            files_processed: Arc::new(AtomicU64::new(5)),
            files_total: Arc::new(AtomicU64::new(10)),
            bytes_original: Arc::new(AtomicU64::new(1000)),
            bytes_compressed: Arc::new(AtomicU64::new(600)),
        };
        let fp = counters.files_processed.clone();
        let (mut reporter, rx) = ProgressReporter::new(counters, "Test".into());


        let progress = rx.recv_timeout(Duration::from_secs(1));
        assert!(progress.is_ok(), "should receive at least one update");
        let p = progress.unwrap();
        assert_eq!(p.files_total, 10);
        assert_eq!(p.bytes_saved, 400);
        fp.store(10, Ordering::Relaxed);
        std::thread::sleep(Duration::from_millis(200));
        reporter.stop();
    }

    #[test]
    fn reporter_completes_on_finish() {
        let counters = EngineCounters {
            files_processed: Arc::new(AtomicU64::new(10)),
            files_total: Arc::new(AtomicU64::new(10)),
            bytes_original: Arc::new(AtomicU64::new(1000)),
            bytes_compressed: Arc::new(AtomicU64::new(600)),
        };
        let (mut reporter, rx) = ProgressReporter::new(counters, "Test".into());

        std::thread::sleep(Duration::from_millis(300));

        let mut found_complete = false;
        while let Ok(p) = rx.try_recv() {
            if p.is_complete {
                found_complete = true;
            }
        }
        assert!(found_complete, "should have sent a completion snapshot");
        reporter.stop();
    }
}
