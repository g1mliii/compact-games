use super::{
    auto_status_sinks_lock, automation_queue_sinks_lock, scheduler_state_sinks_lock,
    shared_state_lock, watcher_event_sinks_lock,
};
use crate::api::automation_types::{FrbAutomationJob, FrbSchedulerState, FrbWatcherEvent};
use crate::automation::scheduler::{AutoScheduler, SchedulerState};
use crate::automation::watcher::{GameWatcher, WatchEvent};

pub(super) fn broadcast_auto_status(is_running: bool) {
    let mut guard = auto_status_sinks_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("AUTO status sinks lock poisoned during broadcast; recovering");
        poisoned.into_inner()
    });
    guard.retain(|sink| sink.add(is_running).is_ok());
}

pub(super) fn broadcast_watcher_event(event: &WatchEvent) {
    let mut guard = watcher_event_sinks_lock()
        .lock()
        .unwrap_or_else(|poisoned| {
            log::warn!("Watcher event sinks lock poisoned; recovering");
            poisoned.into_inner()
        });
    if guard.is_empty() {
        return;
    }
    let frb_event: FrbWatcherEvent = event.clone().into();
    guard.retain(|sink| sink.add(frb_event.clone()).is_ok());
}

pub(super) fn broadcast_scheduler_state(state: SchedulerState) {
    let frb_state: FrbSchedulerState = state.into();
    let mut guard = scheduler_state_sinks_lock()
        .lock()
        .unwrap_or_else(|poisoned| {
            log::warn!("Scheduler state sinks lock poisoned; recovering");
            poisoned.into_inner()
        });
    guard.retain(|sink| sink.add(frb_state).is_ok());
}

pub(super) fn broadcast_automation_queue(jobs: Vec<crate::automation::scheduler::AutomationJob>) {
    let mut guard = automation_queue_sinks_lock()
        .lock()
        .unwrap_or_else(|poisoned| {
            log::warn!("Automation queue sinks lock poisoned; recovering");
            poisoned.into_inner()
        });
    if guard.is_empty() {
        return;
    }
    let frb_jobs: Vec<FrbAutomationJob> = jobs.into_iter().map(Into::into).collect();
    guard.retain(|sink| sink.add(frb_jobs.clone()).is_ok());
}

pub(super) fn update_shared_state(scheduler: &AutoScheduler, watcher: &GameWatcher) {
    let mut guard = shared_state_lock().lock().unwrap_or_else(|poisoned| {
        log::warn!("Shared state lock poisoned during update; recovering");
        poisoned.into_inner()
    });
    guard.scheduler_state = scheduler.state().into();
    guard.queue = scheduler
        .queue_snapshot()
        .into_iter()
        .map(Into::into)
        .collect();
    guard.watched_path_count = if watcher.is_running() {
        watcher.watched_path_count() as u32
    } else {
        0
    };
    guard.queue_depth = scheduler.pending_queue_len() as u32;
}
