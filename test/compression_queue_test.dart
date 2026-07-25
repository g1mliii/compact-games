import 'dart:async';

import 'package:compact_games/models/compression_algorithm.dart';
import 'package:compact_games/models/compression_progress.dart';
import 'package:compact_games/models/managed_restore_plan.dart';
import 'package:compact_games/providers/compression/compression_provider.dart';
import 'package:compact_games/providers/compression/compression_state.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/restore/restore_games_provider.dart';
import 'package:compact_games/services/managed_restore_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/noop_rust_bridge_service.dart';

void main() {
  test('manual jobs run FIFO across compression and decompression', () async {
    final bridge = _QueuedCompressionBridge();
    final container = ProviderContainer(
      overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
    addTearDown(bridge.dispose);
    final notifier = container.read(compressionProvider.notifier);

    await notifier.startCompression(gamePath: r'C:\Games\A', gameName: 'A');
    await notifier.startCompression(
      gamePath: r'C:\Games\B',
      gameName: 'B',
      algorithm: CompressionAlgorithm.lzx,
      allowDirectStorageOverride: true,
    );
    await notifier.startDecompression(gamePath: r'C:\Games\C', gameName: 'C');

    var state = container.read(compressionProvider);
    expect(state.activeJob?.gameName, 'A');
    expect(state.queue.map((job) => job.gameName), <String>['B', 'C']);
    expect(state.queue.first.status, CompressionJobStatus.pending);
    expect(state.queue.first.algorithm, CompressionAlgorithm.lzx);
    expect(state.queue.first.allowDirectStorageOverride, isTrue);
    expect(bridge.startedPaths, <String>[r'C:\Games\A']);

    // Dedupe is path-based and case-insensitive.
    await notifier.startCompression(gamePath: 'c:/games/b/', gameName: 'B');
    expect(container.read(compressionProvider).queueLength, 2);

    bridge.finishActive();
    await _flushStreamEvents();

    state = container.read(compressionProvider);
    expect(state.activeJob?.gameName, 'B');
    expect(state.queue.single.gameName, 'C');
    expect(bridge.startedPaths, <String>[r'C:\Games\A', r'C:\Games\B']);

    bridge.finishActive();
    await _flushStreamEvents();

    state = container.read(compressionProvider);
    expect(state.activeJob?.gameName, 'C');
    expect(state.queue, isEmpty);
    expect(state.activeJob?.type, CompressionJobType.decompression);
    expect(bridge.startedPaths, <String>[
      r'C:\Games\A',
      r'C:\Games\B',
      r'C:\Games\C',
    ]);
  });

  test('removing a queued job preserves order and the active job', () async {
    final bridge = _QueuedCompressionBridge();
    final container = ProviderContainer(
      overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
    addTearDown(bridge.dispose);
    final notifier = container.read(compressionProvider.notifier);

    await notifier.startCompression(gamePath: r'C:\Games\A', gameName: 'A');
    await notifier.startCompression(gamePath: r'C:\Games\B', gameName: 'B');
    await notifier.startCompression(gamePath: r'C:\Games\C', gameName: 'C');

    final runId = container.read(compressionProvider).queue.first.runId;
    notifier.removeFromQueue(runId);

    final state = container.read(compressionProvider);
    expect(state.activeJob?.gameName, 'A');
    expect(state.queue.map((job) => job.gameName), <String>['C']);
    expect(bridge.startedPaths, <String>[r'C:\Games\A']);
  });

  test('cancelling active job drains without clearing pending jobs', () async {
    final bridge = _QueuedCompressionBridge();
    final container = ProviderContainer(
      overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
    addTearDown(bridge.dispose);
    final notifier = container.read(compressionProvider.notifier);

    await notifier.startCompression(gamePath: r'C:\Games\A', gameName: 'A');
    await notifier.startCompression(gamePath: r'C:\Games\B', gameName: 'B');

    notifier.cancelCompression();
    expect(
      container.read(compressionProvider).activeJob?.status,
      CompressionJobStatus.cancelled,
    );
    expect(container.read(compressionProvider).queue.single.gameName, 'B');

    await _flushStreamEvents();

    final state = container.read(compressionProvider);
    expect(state.activeJob?.gameName, 'B');
    expect(state.queue, isEmpty);
    expect(bridge.cancelCalls, 1);
  });

  test(
    'queued waiters complete as cancelled when removed or cleared',
    () async {
      final bridge = _QueuedCompressionBridge();
      final container = ProviderContainer(
        overrides: [rustBridgeServiceProvider.overrideWithValue(bridge)],
      );
      addTearDown(container.dispose);
      addTearDown(bridge.dispose);
      final notifier = container.read(compressionProvider.notifier);

      await notifier.startCompression(gamePath: r'C:\Games\A', gameName: 'A');
      final completion = notifier.startDecompressionAndWait(
        gamePath: r'C:\Games\B',
        gameName: 'B',
      );
      await Future<void>.delayed(Duration.zero);

      notifier.clearQueue();

      expect(await completion, CompressionJobStatus.cancelled);
      expect(container.read(compressionProvider).activeJob?.gameName, 'A');
      expect(container.read(compressionProvider).queue, isEmpty);
    },
  );

  test('completed compression refreshes an open restore plan', () async {
    final bridge = _QueuedCompressionBridge();
    var isManagedCompressed = false;
    final planService = _ChangingManagedRestoreService(
      () => isManagedCompressed
          ? const ManagedRestorePlan(
              games: [
                ManagedRestoreGame(
                  gamePath: r'C:\Games\A',
                  gameName: 'A',
                  drive: r'C:\',
                  requiredBytes: 1_000,
                ),
              ],
              drives: [
                ManagedRestoreDrive(
                  drive: r'C:\',
                  requiredBytes: 1_000,
                  availableBytes: 10_000,
                ),
              ],
            )
          : const ManagedRestorePlan(games: [], drives: []),
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
    await _flushStreamEvents();
    expect(container.read(restoreGamesProvider).plan?.gameCount, 0);

    await container
        .read(compressionProvider.notifier)
        .startCompression(gamePath: r'C:\Games\A', gameName: 'A');
    isManagedCompressed = true;
    bridge.finishActive();
    await _flushStreamEvents();
    await _flushStreamEvents();

    expect(container.read(restoreGamesProvider).plan?.gameCount, 1);
    expect(planService.calls, greaterThanOrEqualTo(2));
  });
}

Future<void> _flushStreamEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _QueuedCompressionBridge extends NoOpRustBridgeService {
  final List<String> startedPaths = <String>[];
  final List<StreamController<CompressionProgress>> _controllers =
      <StreamController<CompressionProgress>>[];
  int cancelCalls = 0;

  Stream<CompressionProgress> _start(String path) {
    startedPaths.add(path);
    final controller = StreamController<CompressionProgress>();
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  Stream<CompressionProgress> compressGame({
    required String gamePath,
    required String gameName,
    CompressionAlgorithm algorithm = CompressionAlgorithm.xpress8k,
    bool allowDirectStorageOverride = false,
    int? ioParallelismOverride,
  }) {
    return _start(gamePath);
  }

  @override
  Stream<CompressionProgress> decompressGame(
    String gamePath, {
    required String gameName,
    int? ioParallelismOverride,
  }) {
    return _start(gamePath);
  }

  @override
  void cancelCompression() {
    cancelCalls += 1;
    finishActive();
  }

  void finishActive() {
    final open = _controllers.where((controller) => !controller.isClosed);
    if (open.isNotEmpty) {
      unawaited(open.first.close());
    }
  }

  void dispose() {
    for (final controller in _controllers) {
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
    }
  }
}

class _ChangingManagedRestoreService extends ManagedRestoreService {
  _ChangingManagedRestoreService(this._readPlan);

  final ManagedRestorePlan Function() _readPlan;
  int calls = 0;

  @override
  Future<ManagedRestorePlan> getPlan() async {
    calls += 1;
    return _readPlan();
  }
}
