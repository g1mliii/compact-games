use std::sync::{Arc, Condvar, Mutex};

use super::{CancellationToken, CompressionEngine};

#[derive(Debug)]
pub(super) struct OperationLock {
    busy: Mutex<bool>,
    available: Condvar,
}

impl OperationLock {
    pub(super) fn new() -> Self {
        Self {
            busy: Mutex::new(false),
            available: Condvar::new(),
        }
    }
}

#[derive(Debug)]
pub(super) struct OperationGuard {
    lock: Arc<OperationLock>,
    released: bool,
}

impl OperationGuard {
    pub(super) fn acquire(lock: Arc<OperationLock>) -> Self {
        let mut busy = match lock.busy.lock() {
            Ok(guard) => guard,
            Err(poisoned) => {
                log::warn!("CompressionEngine operation lock poisoned; continuing");
                poisoned.into_inner()
            }
        };

        while *busy {
            busy = match lock.available.wait(busy) {
                Ok(guard) => guard,
                Err(poisoned) => {
                    log::warn!("CompressionEngine operation wait poisoned; continuing");
                    poisoned.into_inner()
                }
            };
        }

        *busy = true;
        drop(busy);

        Self {
            lock,
            released: false,
        }
    }

    #[cfg(test)]
    pub(super) fn try_acquire(lock: Arc<OperationLock>) -> Option<Self> {
        let mut busy = match lock.busy.lock() {
            Ok(guard) => guard,
            Err(poisoned) => {
                log::warn!("CompressionEngine operation lock poisoned; continuing");
                poisoned.into_inner()
            }
        };

        if *busy {
            return None;
        }

        *busy = true;
        drop(busy);

        Some(Self {
            lock,
            released: false,
        })
    }

    fn release(&mut self) {
        if self.released {
            return;
        }

        let mut busy = match self.lock.busy.lock() {
            Ok(guard) => guard,
            Err(poisoned) => {
                log::warn!("CompressionEngine operation lock poisoned during release; continuing");
                poisoned.into_inner()
            }
        };

        *busy = false;
        self.released = true;
        self.lock.available.notify_one();
    }
}

impl Drop for OperationGuard {
    fn drop(&mut self) {
        self.release();
    }
}

pub(super) struct OperationSession {
    _guard: OperationGuard,
    cancel_token: CancellationToken,
}

impl OperationSession {
    pub(super) fn new(engine: &CompressionEngine) -> Self {
        let guard = engine.operation_guard();
        engine.reset_counters();
        Self {
            _guard: guard,
            cancel_token: engine.cancel_token.clone(),
        }
    }
}

impl Drop for OperationSession {
    fn drop(&mut self) {
        self.cancel_token.reset();
    }
}
