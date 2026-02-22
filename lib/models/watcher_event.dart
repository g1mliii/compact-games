/// Type of watcher event.
enum WatcherEventType { installed, modified, uninstalled }

/// A file-system watcher event from the Rust backend.
class WatcherEvent {
  final WatcherEventType type;
  final String gamePath;
  final String? gameName;
  final DateTime timestamp;

  const WatcherEvent({
    required this.type,
    required this.gamePath,
    this.gameName,
    required this.timestamp,
  });
}
