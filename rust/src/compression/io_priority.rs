//! Background I/O priority for bulk file work.
//!
//! Thread count alone does not stop a bulk operation from starving the machine:
//! a handful of threads issuing large sequential writes will saturate the disk
//! queue, and every other process — including this app's own UI thread — then
//! waits behind them. Windows exposes a per-thread background mode that drops
//! I/O (and memory) priority below every foreground request, which is the
//! mechanism that keeps the rest of the system responsive while the work runs.
//!
//! Scope is per-thread and must be balanced: a thread that enters background
//! mode keeps it until it leaves, so pool workers pair [`enter_background_io`]
//! on start with [`leave_background_io`] on exit.

/// Puts the calling thread into background I/O priority.
///
/// Best effort: a failure means the work runs at normal priority, which is the
/// behaviour we had before, so it is logged rather than surfaced as an error.
#[cfg(windows)]
pub fn enter_background_io() {
    use windows::Win32::System::Threading::{
        GetCurrentThread, SetThreadPriority, THREAD_MODE_BACKGROUND_BEGIN,
    };

    // SAFETY: GetCurrentThread returns a pseudo-handle to this thread that needs
    // no close, and SetThreadPriority only reads it.
    let result = unsafe { SetThreadPriority(GetCurrentThread(), THREAD_MODE_BACKGROUND_BEGIN) };
    if let Err(error) = result {
        log::debug!("Could not enter background I/O priority: {error}");
    }
}

/// Restores normal I/O priority for the calling thread.
#[cfg(windows)]
pub fn leave_background_io() {
    use windows::Win32::System::Threading::{
        GetCurrentThread, SetThreadPriority, THREAD_MODE_BACKGROUND_END,
    };

    // SAFETY: see enter_background_io.
    let result = unsafe { SetThreadPriority(GetCurrentThread(), THREAD_MODE_BACKGROUND_END) };
    if let Err(error) = result {
        log::debug!("Could not leave background I/O priority: {error}");
    }
}

#[cfg(not(windows))]
pub fn enter_background_io() {}

#[cfg(not(windows))]
pub fn leave_background_io() {}
