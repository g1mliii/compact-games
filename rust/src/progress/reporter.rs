//! Progress reporter that polls atomic counters on a dedicated thread
//! and sends `CompressionProgress` snapshots over a bounded channel.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crossbeam_channel::{bounded, Receiver, Sender, TryRecvError, TrySendError};

use super::tracker::CompressionProgress;

pub struct EngineCounters {
    pub files_processed: Arc<AtomicU64>,
    pub files_total: Arc<AtomicU64>,
    pub bytes_original: Arc<AtomicU64>,
    pub bytes_compressed: Arc<AtomicU64>,
}

pub struct ProgressReporter {
    stop: Arc<AtomicBool>,
    done: Arc<AtomicBool>,
    handle: Option<std::thread::JoinHandle<()>>,
}

impl ProgressReporter {
    pub fn new(
        counters: EngineCounters,
        game_name: Arc<str>,
    ) -> (Self, Receiver<CompressionProgress>) {
        Self::new_with_baseline(counters, game_name, false)
    }

    pub fn new_with_baseline(
        counters: EngineCounters,
        game_name: Arc<str>,
        emit_baseline_first: bool,
    ) -> (Self, Receiver<CompressionProgress>) {
        // Keep memory bounded while preserving the newest progress snapshot.
        let (tx, rx) = bounded(1);
        let latest_rx = rx.clone();
        let stop = Arc::new(AtomicBool::new(false));
        let done = Arc::new(AtomicBool::new(false));
        let stop_clone = stop.clone();
        let done_clone = done.clone();

        let handle = std::thread::spawn(move || {
            reporter_loop(
                counters,
                game_name,
                tx,
                latest_rx,
                stop_clone,
                done_clone,
                emit_baseline_first,
            );
        });

        (
            Self {
                stop,
                done,
                handle: Some(handle),
            },
            rx,
        )
    }

    pub fn mark_done(&self) {
        self.done.store(true, Ordering::Relaxed);
    }

    pub fn stop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(h) = self.handle.take() {
            h.thread().unpark();
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
    game_name: Arc<str>,
    tx: Sender<CompressionProgress>,
    latest_rx: Receiver<CompressionProgress>,
    stop: Arc<AtomicBool>,
    done: Arc<AtomicBool>,
    emit_baseline_first: bool,
) {
    let mut speed_samples: VecDeque<f64> = VecDeque::with_capacity(10);
    let mut speed_sum = 0.0;
    let mut last_files: u64 = 0;
    let mut last_tick = Instant::now();
    let mut last_emitted: Option<(u64, u64, u64, u64, bool)> = None;
    let mut baseline_pending = emit_baseline_first;

    loop {
        // park_timeout lets stop() wake this thread immediately via unpark().
        std::thread::park_timeout(Duration::from_millis(100));

        let stopping = stop.load(Ordering::Relaxed);
        let done_now = done.load(Ordering::Relaxed);

        let files_processed_raw = counters.files_processed.load(Ordering::Relaxed);
        let files_total_raw = counters.files_total.load(Ordering::Relaxed);
        // Atomic snapshots can be observed out-of-sync across counters; normalize
        // for display while keeping completion tied to explicit done signaling.
        let files_total = if done_now {
            files_total_raw.max(files_processed_raw)
        } else if files_processed_raw > files_total_raw {
            files_processed_raw.saturating_add(1)
        } else {
            files_total_raw
        };
        let files_processed = files_processed_raw.min(files_total);
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

        if baseline_pending {
            if files_total == 0 && !done_now && !stopping {
                continue;
            }

            let baseline_is_complete = done_now && files_total == 0;
            let baseline = CompressionProgress {
                game_name: game_name.clone(),
                files_total,
                files_processed: 0,
                bytes_original: 0,
                bytes_compressed: 0,
                bytes_saved: 0,
                estimated_time_remaining: None,
                is_complete: baseline_is_complete,
            };
            if !send_latest(&tx, &latest_rx, baseline) {
                break;
            }
            last_emitted = Some((0, files_total, 0, 0, baseline_is_complete));
            baseline_pending = false;
            if baseline_is_complete {
                break;
            }
            continue;
        }

        let is_complete = done_now;
        let emit_key = (
            files_processed,
            files_total,
            bytes_original,
            bytes_compressed,
            is_complete,
        );
        let should_emit = last_emitted != Some(emit_key) || stopping;

        if should_emit {
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

            if !send_latest(&tx, &latest_rx, progress) {
                break;
            }
            last_emitted = Some(emit_key);
        }

        if is_complete || stopping {
            break;
        }
    }
}

fn send_latest(
    tx: &Sender<CompressionProgress>,
    latest_rx: &Receiver<CompressionProgress>,
    progress: CompressionProgress,
) -> bool {
    match tx.try_send(progress) {
        Ok(()) => true,
        Err(TrySendError::Full(progress)) => {
            match latest_rx.try_recv() {
                Ok(_) | Err(TryRecvError::Empty) => {}
                Err(TryRecvError::Disconnected) => return false,
            }
            tx.try_send(progress).is_ok()
        }
        Err(TrySendError::Disconnected(_)) => false,
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
        let (mut reporter, _rx) = ProgressReporter::new(counters, Arc::from("Test"));
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
        let (mut reporter, rx) = ProgressReporter::new(counters, Arc::from("Test"));

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
        let (mut reporter, rx) = ProgressReporter::new(counters, Arc::from("Test"));
        reporter.mark_done();
        let completed = rx
            .recv_timeout(Duration::from_secs(1))
            .expect("should receive completion snapshot");
        assert!(
            completed.is_complete,
            "should have sent completion snapshot"
        );
        reporter.stop();
    }

    #[test]
    fn reporter_marks_complete_for_empty_operation_when_done_signaled() {
        let counters = EngineCounters {
            files_processed: Arc::new(AtomicU64::new(0)),
            files_total: Arc::new(AtomicU64::new(0)),
            bytes_original: Arc::new(AtomicU64::new(0)),
            bytes_compressed: Arc::new(AtomicU64::new(0)),
        };
        let (mut reporter, rx) = ProgressReporter::new(counters, Arc::from("Empty"));
        reporter.mark_done();

        let progress = rx.recv_timeout(Duration::from_secs(1)).unwrap();
        assert!(progress.is_complete, "done signal should force completion");
        reporter.stop();
    }

    #[test]
    fn reporter_never_reports_processed_above_total() {
        let counters = EngineCounters {
            files_processed: Arc::new(AtomicU64::new(10)),
            files_total: Arc::new(AtomicU64::new(1)),
            bytes_original: Arc::new(AtomicU64::new(1000)),
            bytes_compressed: Arc::new(AtomicU64::new(600)),
        };

        let (mut reporter, rx) = ProgressReporter::new(counters, Arc::from("Clamp"));
        let progress = rx.recv_timeout(Duration::from_secs(1)).unwrap();

        assert!(
            progress.files_processed <= progress.files_total,
            "processed should never exceed total in reported snapshots",
        );
        reporter.stop();
    }

    #[test]
    fn reporter_does_not_mark_complete_until_done_signal() {
        let counters = EngineCounters {
            files_processed: Arc::new(AtomicU64::new(10)),
            files_total: Arc::new(AtomicU64::new(1)),
            bytes_original: Arc::new(AtomicU64::new(1000)),
            bytes_compressed: Arc::new(AtomicU64::new(600)),
        };

        let (mut reporter, rx) = ProgressReporter::new(counters, Arc::from("CompleteGate"));
        let first = rx.recv_timeout(Duration::from_secs(1)).unwrap();
        assert!(
            !first.is_complete,
            "completion must wait for explicit done signal",
        );

        reporter.mark_done();
        let second = rx.recv_timeout(Duration::from_secs(1)).unwrap();
        assert!(
            second.is_complete,
            "reporter should emit completion snapshot after done signal",
        );
        reporter.stop();
    }

    #[test]
    fn reporter_baseline_emits_zero_processed_first_snapshot() {
        let counters = EngineCounters {
            files_processed: Arc::new(AtomicU64::new(5)),
            files_total: Arc::new(AtomicU64::new(10)),
            bytes_original: Arc::new(AtomicU64::new(1_000)),
            bytes_compressed: Arc::new(AtomicU64::new(600)),
        };

        let (mut reporter, rx) =
            ProgressReporter::new_with_baseline(counters, Arc::from("Baseline"), true);
        let first = rx.recv_timeout(Duration::from_secs(1)).unwrap();

        assert_eq!(first.files_total, 10);
        assert_eq!(first.files_processed, 0);
        assert_eq!(first.bytes_original, 0);
        assert_eq!(first.bytes_compressed, 0);
        assert_eq!(first.bytes_saved, 0);

        reporter.stop();
    }
}
