import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../games/game_list_provider.dart' show rustBridgeServiceProvider;
import '../settings/settings_provider.dart';
import 'update_provider.dart';

typedef UpdateCheckClock = DateTime Function();
typedef UpdateCheckTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// Owns the single automatic-update timer for the process.
///
/// The coordinator deliberately retains only one timer, one timestamp, and one
/// in-flight flag. It has no stream subscription, isolate, cache, or network
/// client of its own. The instance is stable for the life of the container:
/// toggling automatic checks flips [UpdateCheckCoordinator.setEnabled] rather
/// than rebuilding it, so the rate limit and any in-flight check survive.
final updateCheckCoordinatorProvider = Provider<UpdateCheckCoordinator>((ref) {
  final coordinator = UpdateCheckCoordinator(
    // Owned by Rust, which rate-limits the check itself — scheduling any faster
    // would only wake up to read Rust's cache.
    interval: ref.read(rustBridgeServiceProvider).updateCheckInterval,
    now: DateTime.now,
    createTimer: Timer.new,
    performCheck: () async {
      await ref.read(updateProvider.future);
      await ref.read(updateProvider.notifier).checkForUpdate(automatic: true);
    },
  );
  ref.onDispose(coordinator.dispose);

  // Listened rather than watched: a settings toggle flips the existing
  // coordinator instead of rebuilding this provider, so the rate limit and any
  // in-flight check survive it. `selfUpdatesEnabled` is a build-time constant
  // and needs no listener. Settings load asynchronously, so the initial sync
  // usually resolves to false and the listener turns it on a moment later.
  void syncEnabled(bool? autoCheckUpdates) {
    coordinator.setEnabled(
      ref.read(selfUpdatesEnabledProvider) && autoCheckUpdates == true,
    );
  }

  final autoCheckUpdates = settingsProvider.select(
    (s) => s.value?.settings.autoCheckUpdates,
  );
  ref.listen(autoCheckUpdates, (_, next) => syncEnabled(next));
  syncEnabled(ref.read(autoCheckUpdates));

  return coordinator;
});

class UpdateCheckCoordinator {
  /// Starts disabled; [setEnabled] is the only way in, so construction never
  /// has a side effect.
  UpdateCheckCoordinator({
    required this.interval,
    required this.now,
    required this.createTimer,
    required this.performCheck,
  });

  final Duration interval;
  final UpdateCheckClock now;
  final UpdateCheckTimerFactory createTimer;
  final Future<void> Function() performCheck;

  bool _enabled = false;
  DateTime? _lastAttemptAt;
  Timer? _timer;
  bool _inFlight = false;
  bool _disposed = false;

  bool get enabled => _enabled;

  /// Turns automatic checking on or off. Enabling runs a check if one is due
  /// and otherwise arms the timer for the rest of the interval; disabling drops
  /// the timer but keeps the last attempt time, so re-enabling cannot be used
  /// to hammer the update endpoint.
  void setEnabled(bool enabled) {
    if (_disposed || enabled == _enabled) {
      return;
    }
    _enabled = enabled;
    if (!enabled) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    unawaited(_attemptIfDue());
  }

  /// Called by the app's existing hidden-to-visible lifecycle callback.
  void onWindowVisible() => unawaited(_attemptIfDue());

  Future<void> _attemptIfDue() async {
    if (!_enabled || _disposed || _inFlight) {
      return;
    }

    final currentTime = now();
    final lastAttemptAt = _lastAttemptAt;
    if (lastAttemptAt != null &&
        currentTime.isBefore(lastAttemptAt.add(interval))) {
      // The timer callback clears its own handle before landing here, so a
      // wakeup that turns out not to be due — any backward wall-clock move,
      // e.g. DST fall-back — would otherwise end the chain for good.
      if (_timer == null) {
        _scheduleNextAttempt();
      }
      return;
    }

    _timer?.cancel();
    _timer = null;
    _lastAttemptAt = currentTime;
    _inFlight = true;
    try {
      await performCheck();
    } catch (_) {
      // Best effort. The attempt timestamp still prevents rapid offline retries.
    } finally {
      _inFlight = false;
      if (!_disposed) {
        _scheduleNextAttempt();
      }
    }
  }

  void _scheduleNextAttempt() {
    final lastAttemptAt = _lastAttemptAt;
    if (!_enabled || _disposed || lastAttemptAt == null) {
      return;
    }

    final remaining = lastAttemptAt.add(interval).difference(now());
    final delay = remaining.isNegative ? Duration.zero : remaining;
    _timer?.cancel();
    _timer = createTimer(delay, () {
      _timer = null;
      unawaited(_attemptIfDue());
    });
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
