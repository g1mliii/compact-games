#![allow(dead_code)]

use std::sync::{Mutex, MutexGuard};

static DISCOVERY_TEST_MUTEX: Mutex<()> = Mutex::new(());

pub(crate) fn lock_discovery_test() -> MutexGuard<'static, ()> {
    DISCOVERY_TEST_MUTEX
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}
