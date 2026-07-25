import 'dart:async';

import 'package:compact_games/models/compression_progress.dart';
import 'package:compact_games/models/managed_restore_plan.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/restore/restore_games_provider.dart';
import 'package:compact_games/providers/restore/restore_gate_provider.dart';
import 'package:compact_games/services/managed_restore_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/noop_rust_bridge_service.dart';

void main() {
  test(
    'restore preflights again, queues decompression FIFO, and unlocks uninstall',
    () async {
      final bridge = _RestoreQueueBridge();
      final fullPlan = _plan(availableBytes: 20_000);
      final planService = _FakeManagedRestoreService(
        () => bridge.completedPaths.length == 2
            ? const ManagedRestorePlan(games: [], drives: [])
            : fullPlan,
      );
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(bridge),
          managedRestoreServiceProvider.overrideWithValue(planService),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(bridge.dispose);

      container.read(restoreGamesProvider);
      await _flushEvents();
      expect(container.read(restoreGamesProvider).plan?.gameCount, 2);

      final restore = container
          .read(restoreGamesProvider.notifier)
          .restoreAll();
      await _flushEvents();

      expect(container.read(restoreGateProvider), isTrue);
      expect(bridge.startedPaths, <String>[r'C:\Games\A']);
      expect(container.read(restoreGamesProvider).isRestoring, isTrue);

      bridge.finishActive();
      await _flushEvents();
      expect(bridge.startedPaths, <String>[r'C:\Games\A', r'C:\Games\B']);

      bridge.finishActive();
      await restore;

      final state = container.read(restoreGamesProvider);
      expect(state.canOfferUninstall, isTrue);
      expect(state.completedGames, 2);
      expect(state.failures, isEmpty);
      expect(container.read(restoreGateProvider), isFalse);
      expect(bridge.stopAutomationCalls, greaterThanOrEqualTo(1));
      expect(planService.calls, greaterThanOrEqualTo(3));
    },
  );

  test('restore refuses to queue when a drive lacks free space', () async {
    final bridge = _RestoreQueueBridge();
    final container = ProviderContainer(
      overrides: [
        rustBridgeServiceProvider.overrideWithValue(bridge),
        managedRestoreServiceProvider.overrideWithValue(
          _FakeManagedRestoreService(() => _plan(availableBytes: 500)),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(bridge.dispose);

    container.read(restoreGamesProvider);
    await _flushEvents();
    await container.read(restoreGamesProvider.notifier).restoreAll();

    expect(bridge.startedPaths, isEmpty);
    expect(container.read(restoreGateProvider), isFalse);
    expect(container.read(restoreGamesProvider).plan?.hasEnoughSpace, isFalse);
  });

  test(
    'failed restore releases the gate and keeps the failure skippable',
    () async {
      final bridge = _RestoreQueueBridge();
      final singlePlan = ManagedRestorePlan(
        games: const [
          ManagedRestoreGame(
            gamePath: r'C:\Games\A',
            gameName: 'A',
            drive: r'C:\',
            requiredBytes: 1_000,
          ),
        ],
        drives: const [
          ManagedRestoreDrive(
            drive: r'C:\',
            requiredBytes: 1_000,
            availableBytes: 5_000,
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          rustBridgeServiceProvider.overrideWithValue(bridge),
          managedRestoreServiceProvider.overrideWithValue(
            _FakeManagedRestoreService(() => singlePlan),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(bridge.dispose);

      container.read(restoreGamesProvider);
      await _flushEvents();
      final restore = container
          .read(restoreGamesProvider.notifier)
          .restoreAll();
      await _flushEvents();
      bridge.failActive('locked file');
      await restore;

      expect(container.read(restoreGamesProvider).failures, hasLength(1));
      // The run has stopped, so the gate is released even with failures pending:
      // holding it would block every manual and automatic compression app-wide
      // with no user feedback. Each retry re-pauses it for its own decompression.
      expect(container.read(restoreGateProvider), isFalse);

      await container
          .read(restoreGamesProvider.notifier)
          .skipFailure(r'C:\Games\A');

      final state = container.read(restoreGamesProvider);
      expect(state.failures, isEmpty);
      expect(state.skippedGames, hasLength(1));
      expect(state.canOfferUninstall, isFalse);
      expect(container.read(restoreGateProvider), isFalse);
    },
  );
}

ManagedRestorePlan _plan({required int availableBytes}) {
  return ManagedRestorePlan(
    games: const [
      ManagedRestoreGame(
        gamePath: r'C:\Games\A',
        gameName: 'A',
        drive: r'C:\',
        requiredBytes: 1_000,
      ),
      ManagedRestoreGame(
        gamePath: r'C:\Games\B',
        gameName: 'B',
        drive: r'C:\',
        requiredBytes: 2_000,
      ),
    ],
    drives: [
      ManagedRestoreDrive(
        drive: r'C:\',
        requiredBytes: 3_000,
        availableBytes: availableBytes,
      ),
    ],
  );
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeManagedRestoreService extends ManagedRestoreService {
  _FakeManagedRestoreService(this._readPlan);

  final ManagedRestorePlan Function() _readPlan;
  int calls = 0;

  @override
  Future<ManagedRestorePlan> getPlan() async {
    calls += 1;
    return _readPlan();
  }
}

class _RestoreQueueBridge extends NoOpRustBridgeService {
  final List<String> startedPaths = <String>[];
  final List<String> completedPaths = <String>[];
  final List<StreamController<CompressionProgress>> _controllers =
      <StreamController<CompressionProgress>>[];
  int stopAutomationCalls = 0;

  @override
  Stream<CompressionProgress> decompressGame(
    String gamePath, {
    required String gameName,
    int? ioParallelismOverride,
  }) {
    startedPaths.add(gamePath);
    final controller = StreamController<CompressionProgress>();
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  void stopAutoCompression() {
    stopAutomationCalls += 1;
  }

  void finishActive() {
    final index = _controllers.indexWhere((controller) => !controller.isClosed);
    if (index < 0) return;
    completedPaths.add(startedPaths[index]);
    unawaited(_controllers[index].close());
  }

  void failActive(String message) {
    final controller = _controllers.firstWhere(
      (candidate) => !candidate.isClosed,
    );
    controller.addError(StateError(message));
  }

  void dispose() {
    for (final controller in _controllers) {
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
    }
  }
}
