import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/compression_algorithm.dart';
import '../games/game_list_provider.dart';
import '../settings/settings_provider.dart';

/// Reactive settings sync: when automation-relevant settings change,
/// push the new config to the Rust backend.
///
/// Lesson 32: no polling timers - all state via Rust->Dart streams.
/// Uses .select() to avoid re-evaluating on unrelated settings changes
/// (e.g. theme, notifications, API keys).
final automationSettingsSyncProvider = Provider<void>((ref) {
  final autoCompress = ref.watch(settingsProvider.select(
    (async) => async.valueOrNull?.settings.autoCompress,
  ));
  final cpuThreshold = ref.watch(settingsProvider.select(
    (async) => async.valueOrNull?.settings.cpuThreshold,
  ));
  final idleDurationMinutes = ref.watch(settingsProvider.select(
    (async) => async.valueOrNull?.settings.idleDurationMinutes,
  ));
  final cooldownMinutes = ref.watch(settingsProvider.select(
    (async) => async.valueOrNull?.settings.cooldownMinutes,
  ));
  final customFolders = ref.watch(settingsProvider.select(
    (async) => async.valueOrNull?.settings.customFolders,
  ));
  final excludedPaths = ref.watch(settingsProvider.select(
    (async) => async.valueOrNull?.settings.excludedPaths,
  ));
  final algorithm = ref.watch(settingsProvider.select(
    (async) => async.valueOrNull?.settings.algorithm,
  ));

  if (autoCompress == null) return;

  final bridge = ref.read(rustBridgeServiceProvider);

  if (autoCompress) {
    bridge.updateAutomationConfig(
      cpuThresholdPercent: cpuThreshold!,
      idleDurationSeconds: idleDurationMinutes! * 60,
      cooldownSeconds: cooldownMinutes! * 60,
      watchPaths: customFolders ?? const [],
      excludedPaths: excludedPaths ?? const [],
      algorithm: algorithm ?? CompressionAlgorithm.xpress8k,
    );
    bridge.startAutoCompression();
  } else {
    bridge.stopAutoCompression();
  }
});
