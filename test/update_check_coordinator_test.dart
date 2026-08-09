import 'dart:async';

import 'package:compact_games/models/app_settings.dart';
import 'package:compact_games/providers/settings/settings_provider.dart';
import 'package:compact_games/providers/settings/settings_state.dart';
import 'package:compact_games/providers/update/update_check_coordinator.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/update/update_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/noop_rust_bridge_service.dart';

/// The coordinator takes its interval as a parameter; production reads Rust's.
const Duration _interval = Duration(hours: 6);

void main() {
  test('the provider enables the coordinator once settings resolve', () async {
    final settings = _TestSettingsNotifier();
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => settings),
        selfUpdatesEnabledProvider.overrideWithValue(true),
        rustBridgeServiceProvider.overrideWithValue(
          const NoOpRustBridgeService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final coordinator = container.read(updateCheckCoordinatorProvider);
    // The interval comes from Rust, so Dart cannot drift from its rate limit.
    expect(
      coordinator.interval,
      const NoOpRustBridgeService().updateCheckInterval,
    );
    // Settings have not loaded yet, so nothing may run.
    expect(coordinator.enabled, isFalse);

    await container.read(settingsProvider.future);
    await _flushMicrotasks();
    expect(coordinator.enabled, isTrue);

    settings.emitAutoCheckUpdates(false);
    await _flushMicrotasks();
    expect(coordinator.enabled, isFalse);

    // Toggling back on must reach the same instance, not a rebuilt one.
    settings.emitAutoCheckUpdates(true);
    await _flushMicrotasks();
    expect(container.read(updateCheckCoordinatorProvider), same(coordinator));
    expect(coordinator.enabled, isTrue);
  });

  test(
    'enabled coordinator keeps exactly one timer and checks when due',
    () async {
      var now = DateTime.utc(2026, 8, 8, 12);
      var checks = 0;
      final timers = _FakeTimerFactory();
      final coordinator = UpdateCheckCoordinator(
        interval: _interval,
        now: () => now,
        createTimer: timers.create,
        performCheck: () async {
          checks += 1;
        },
      );
      addTearDown(coordinator.dispose);

      coordinator.setEnabled(true);
      await _flushMicrotasks();

      expect(checks, 1);
      expect(timers.activeCount, 1);
      expect(timers.created.length, 1);

      coordinator.onWindowVisible();
      await _flushMicrotasks();

      expect(checks, 1);
      expect(timers.created.length, 1);

      now = now.add(_interval);
      coordinator.onWindowVisible();
      await _flushMicrotasks();

      expect(checks, 2);
      expect(timers.created.length, 2);
      expect(timers.activeCount, 1);
    },
  );

  test('timer callback rechecks and rearms one timer', () async {
    var now = DateTime.utc(2026, 8, 8, 12);
    var checks = 0;
    final timers = _FakeTimerFactory();
    final coordinator = UpdateCheckCoordinator(
      interval: _interval,
      now: () => now,
      createTimer: timers.create,
      performCheck: () async {
        checks += 1;
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.setEnabled(true);
    await _flushMicrotasks();
    now = now.add(_interval);
    timers.singleActive.fire();
    await _flushMicrotasks();

    expect(checks, 2);
    expect(timers.activeCount, 1);
    expect(timers.created.length, 2);
  });

  test('disabled coordinator creates no timer and performs no check', () async {
    final timers = _FakeTimerFactory();
    var checks = 0;
    final coordinator = UpdateCheckCoordinator(
      interval: _interval,
      now: DateTime.now,
      createTimer: timers.create,
      performCheck: () async {
        checks += 1;
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.onWindowVisible();
    await _flushMicrotasks();

    expect(checks, 0);
    expect(timers.created, isEmpty);
  });

  test('failed attempts are rate-limited and still rearm the timer', () async {
    var now = DateTime.utc(2026, 8, 8, 12);
    final timers = _FakeTimerFactory();
    var checks = 0;
    final coordinator = UpdateCheckCoordinator(
      interval: _interval,
      now: () => now,
      createTimer: timers.create,
      performCheck: () async {
        checks += 1;
        throw StateError('offline');
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.setEnabled(true);
    await _flushMicrotasks();
    coordinator.onWindowVisible();
    await _flushMicrotasks();

    expect(checks, 1);
    expect(timers.activeCount, 1);

    now = now.add(_interval);
    coordinator.onWindowVisible();
    await _flushMicrotasks();

    expect(checks, 2);
    expect(timers.activeCount, 1);
  });

  test('a wakeup that is not due rearms instead of ending the chain', () async {
    var now = DateTime.utc(2026, 8, 8, 12);
    var checks = 0;
    final timers = _FakeTimerFactory();
    final coordinator = UpdateCheckCoordinator(
      interval: _interval,
      now: () => now,
      createTimer: timers.create,
      performCheck: () async {
        checks += 1;
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.setEnabled(true);
    await _flushMicrotasks();
    expect(checks, 1);

    // Timers count elapsed real time; the wall clock can move backwards under
    // it (DST fall-back, NTP correction), so a firing timer may not be due.
    now = now.add(_interval - const Duration(hours: 1));
    timers.singleActive.fire();
    await _flushMicrotasks();

    expect(checks, 1);
    expect(timers.activeCount, 1);

    now = now.add(const Duration(hours: 1));
    timers.singleActive.fire();
    await _flushMicrotasks();

    expect(checks, 2);
    expect(timers.activeCount, 1);
  });

  test('toggling the setting off and on keeps the rate limit', () async {
    var now = DateTime.utc(2026, 8, 8, 12);
    var checks = 0;
    final timers = _FakeTimerFactory();
    final coordinator = UpdateCheckCoordinator(
      interval: _interval,
      now: () => now,
      createTimer: timers.create,
      performCheck: () async {
        checks += 1;
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.setEnabled(true);
    await _flushMicrotasks();
    expect(checks, 1);

    // Toggling the setting off drops the timer but must not clear the attempt
    // time, so turning it back on cannot be used to re-check on demand.
    coordinator.setEnabled(false);
    expect(timers.activeCount, 0);

    coordinator.setEnabled(true);
    await _flushMicrotasks();

    expect(checks, 1);
    expect(timers.activeCount, 1);

    now = now.add(_interval);
    timers.singleActive.fire();
    await _flushMicrotasks();

    expect(checks, 2);
  });

  test(
    'in-flight check cannot overlap and dispose cancels its timer',
    () async {
      var now = DateTime.utc(2026, 8, 8, 12);
      final timers = _FakeTimerFactory();
      final pending = Completer<void>();
      var checks = 0;
      final coordinator = UpdateCheckCoordinator(
        interval: _interval,
        now: () => now,
        createTimer: timers.create,
        performCheck: () {
          checks += 1;
          return pending.future;
        },
      );

      coordinator.setEnabled(true);
      await _flushMicrotasks();
      now = now.add(_interval * 2);
      coordinator.onWindowVisible();
      await _flushMicrotasks();

      expect(checks, 1);
      expect(timers.activeCount, 0);

      pending.complete();
      await _flushMicrotasks();
      expect(timers.activeCount, 1);

      coordinator.dispose();
      expect(timers.activeCount, 0);
    },
  );
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
}

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  Future<SettingsState> build() async {
    return const SettingsState(
      settings: AppSettings(autoCheckUpdates: true),
      isLoaded: true,
    );
  }

  void emitAutoCheckUpdates(bool value) {
    final current = state.value ?? const SettingsState();
    state = AsyncValue.data(
      current.copyWith(
        settings: current.settings.copyWith(autoCheckUpdates: value),
      ),
    );
  }
}

class _FakeTimerFactory {
  final List<_FakeTimer> created = <_FakeTimer>[];

  Timer create(Duration delay, void Function() callback) {
    final timer = _FakeTimer(delay, callback);
    created.add(timer);
    return timer;
  }

  int get activeCount => created.where((timer) => timer.isActive).length;

  _FakeTimer get singleActive => created.singleWhere((timer) => timer.isActive);
}

class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
  }

  void fire() {
    if (!_active) {
      return;
    }
    _active = false;
    _tick += 1;
    _callback();
  }
}
