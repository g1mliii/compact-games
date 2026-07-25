import 'pending_signal_dispatcher.dart';

/// Signals that the uninstaller asked the app to open the restore section.
///
/// The signal carries no payload, so repeated launches while the UI is not yet
/// listening collapse into a single replay.
class PrepareUninstallDispatcher extends PendingSignalDispatcher<void> {
  PrepareUninstallDispatcher._() : super(coalescePending: true);

  static final PrepareUninstallDispatcher instance =
      PrepareUninstallDispatcher._();

  void signal() => enqueue(null);
}
