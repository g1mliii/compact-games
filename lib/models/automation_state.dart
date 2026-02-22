/// Scheduler state mirroring Rust's SchedulerState.
enum SchedulerState {
  idle,
  settling,
  waitingForIdle,
  safetyCheck,
  compressing,
  paused,
  backoff,
}

/// Automation job status.
enum AutomationJobStatus {
  pending,
  waitingForSettle,
  waitingForIdle,
  compressing,
  completed,
  failed,
  skipped,
}

/// Automation job kind.
enum AutomationJobKind { newInstall, reconcile, opportunistic }

/// A single automation compression job for UI display.
class AutomationJob {
  final String gamePath;
  final String? gameName;
  final AutomationJobKind kind;
  final AutomationJobStatus status;
  final DateTime queuedAt;
  final DateTime? startedAt;
  final String? error;

  const AutomationJob({
    required this.gamePath,
    this.gameName,
    required this.kind,
    required this.status,
    required this.queuedAt,
    this.startedAt,
    this.error,
  });
}
