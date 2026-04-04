import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/compression_algorithm.dart';
import '../../models/game_info.dart';
import '../games/game_list_provider.dart';
import '../settings/settings_provider.dart';

/// Reactive settings sync: when automation-relevant settings change,
/// push the new config to the Rust backend.
///
/// Lesson 32: no polling timers - all state via Rust->Dart streams.
/// Uses .select() to avoid re-evaluating on unrelated settings changes
/// (e.g. theme, notifications, API keys).
final automationDiscoveredWatchPathsProvider =
    Provider<AutomationDiscoveredWatchPaths>((ref) {
      return ref.watch(
        gameListProvider.select(
          (async) => AutomationDiscoveredWatchPaths.fromGames(
            async.valueOrNull?.games ?? const <GameInfo>[],
          ),
        ),
      );
    });

final automationSyncConfigProvider = Provider<AutomationSyncConfig?>((ref) {
  final autoCompress = ref.watch(
    settingsProvider.select(
      (async) => async.valueOrNull?.settings.autoCompress,
    ),
  );
  final cpuThreshold = ref.watch(
    settingsProvider.select(
      (async) => async.valueOrNull?.settings.cpuThreshold,
    ),
  );
  final idleDurationMinutes = ref.watch(
    settingsProvider.select(
      (async) => async.valueOrNull?.settings.idleDurationMinutes,
    ),
  );
  final cooldownMinutes = ref.watch(
    settingsProvider.select(
      (async) => async.valueOrNull?.settings.cooldownMinutes,
    ),
  );
  final customFolders = ref.watch(
    settingsProvider.select(
      (async) => async.valueOrNull?.settings.customFolders,
    ),
  );
  final discoveredWatchPaths = ref.watch(
    automationDiscoveredWatchPathsProvider,
  );
  final excludedPaths = ref.watch(
    settingsProvider.select(
      (async) => async.valueOrNull?.settings.excludedPaths,
    ),
  );
  final algorithm = ref.watch(
    settingsProvider.select((async) => async.valueOrNull?.settings.algorithm),
  );
  final ioParallelismOverride = ref.watch(
    settingsProvider.select(
      (async) => async.valueOrNull?.settings.ioParallelismOverride,
    ),
  );
  final allowDirectStorageOverride = ref.watch(
    settingsProvider.select(
      (async) => async.valueOrNull?.settings.directStorageOverrideEnabled,
    ),
  );

  if (autoCompress != true) {
    return null;
  }

  final watchPaths = buildAutomationWatchPaths(
    customFolders: customFolders ?? const [],
    discoveredWatchPaths: discoveredWatchPaths.paths,
  );

  return AutomationSyncConfig(
    cpuThresholdPercent: cpuThreshold!,
    idleDurationSeconds: idleDurationMinutes! * 60,
    cooldownSeconds: cooldownMinutes! * 60,
    watchPaths: watchPaths,
    excludedPaths: excludedPaths ?? const [],
    algorithm: algorithm ?? CompressionAlgorithm.xpress8k,
    allowDirectStorageOverride: allowDirectStorageOverride ?? false,
    ioParallelismOverride: ioParallelismOverride,
  );
});

final automationSettingsSyncProvider = Provider<void>((ref) {
  ref.listen<AutomationSyncConfig?>(automationSyncConfigProvider, (
    previous,
    next,
  ) {
    final bridge = ref.read(rustBridgeServiceProvider);
    if (next == null) {
      if (previous == null) {
        return;
      }
      try {
        bridge.stopAutoCompression();
      } catch (error) {
        debugPrint('[automation][sync] stop auto compression failed: $error');
      }
      return;
    }

    _runAutomationSync(
      bridge.updateAutomationConfig(
        cpuThresholdPercent: next.cpuThresholdPercent,
        idleDurationSeconds: next.idleDurationSeconds,
        cooldownSeconds: next.cooldownSeconds,
        watchPaths: next.watchPaths,
        excludedPaths: next.excludedPaths,
        algorithm: next.algorithm,
        allowDirectStorageOverride: next.allowDirectStorageOverride,
        ioParallelismOverride: next.ioParallelismOverride,
      ),
      operation: 'update config',
    );

    if (previous != null) {
      return;
    }

    _runAutomationSync(
      bridge.startAutoCompression(),
      operation: 'start auto compression',
    );
  }, fireImmediately: true);
});

@immutable
class AutomationSyncConfig {
  const AutomationSyncConfig({
    required this.cpuThresholdPercent,
    required this.idleDurationSeconds,
    required this.cooldownSeconds,
    required this.watchPaths,
    required this.excludedPaths,
    required this.algorithm,
    required this.allowDirectStorageOverride,
    required this.ioParallelismOverride,
  });

  final double cpuThresholdPercent;
  final int idleDurationSeconds;
  final int cooldownSeconds;
  final List<String> watchPaths;
  final List<String> excludedPaths;
  final CompressionAlgorithm algorithm;
  final bool allowDirectStorageOverride;
  final int? ioParallelismOverride;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutomationSyncConfig &&
          runtimeType == other.runtimeType &&
          cpuThresholdPercent == other.cpuThresholdPercent &&
          idleDurationSeconds == other.idleDurationSeconds &&
          cooldownSeconds == other.cooldownSeconds &&
          listEquals(watchPaths, other.watchPaths) &&
          listEquals(excludedPaths, other.excludedPaths) &&
          algorithm == other.algorithm &&
          allowDirectStorageOverride == other.allowDirectStorageOverride &&
          ioParallelismOverride == other.ioParallelismOverride;

  @override
  int get hashCode => Object.hash(
    cpuThresholdPercent,
    idleDurationSeconds,
    cooldownSeconds,
    Object.hashAll(watchPaths),
    Object.hashAll(excludedPaths),
    algorithm,
    allowDirectStorageOverride,
    ioParallelismOverride,
  );
}

@immutable
class AutomationDiscoveredWatchPaths {
  const AutomationDiscoveredWatchPaths(this.paths);

  factory AutomationDiscoveredWatchPaths.fromGames(Iterable<GameInfo> games) {
    final seen = <String>{};
    final paths = <String>[];

    for (final game in games) {
      if (game.excluded ||
          game.isUnsupported ||
          game.platform == Platform.application) {
        continue;
      }

      final trimmed = game.path.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final key = _automationWatchPathKey(trimmed);
      if (!seen.add(key)) {
        continue;
      }

      paths.add(trimmed);
    }

    return AutomationDiscoveredWatchPaths(paths);
  }

  final List<String> paths;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutomationDiscoveredWatchPaths && listEquals(paths, other.paths);

  @override
  int get hashCode => Object.hashAll(paths);
}

List<String> buildAutomationWatchPaths({
  required List<String> customFolders,
  Iterable<GameInfo> games = const <GameInfo>[],
  List<String>? discoveredWatchPaths,
}) {
  final seen = <String>{};
  final watchPaths = <String>[];

  void addPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final key = _automationWatchPathKey(trimmed);
    if (!seen.add(key)) {
      return;
    }
    watchPaths.add(trimmed);
  }

  for (final folder in customFolders) {
    addPath(folder);
  }

  if (discoveredWatchPaths != null) {
    for (final path in discoveredWatchPaths) {
      addPath(path);
    }
    return watchPaths;
  }

  for (final path in AutomationDiscoveredWatchPaths.fromGames(games).paths) {
    addPath(path);
  }

  return watchPaths;
}

String _automationWatchPathKey(String path) {
  var normalized = path.replaceAll('/', r'\');
  while (normalized.length > 3 && normalized.endsWith(r'\')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized.toLowerCase();
}

void _runAutomationSync(Future<void> task, {required String operation}) {
  unawaited(
    task.catchError((Object error, StackTrace _) {
      debugPrint('[automation][sync] $operation failed: $error');
    }),
  );
}
