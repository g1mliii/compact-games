import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/automation_state.dart';
import '../games/game_list_provider.dart';

// Not autoDispose — kept alive by trayStatusSyncProvider (via _EffectProviderHost).
final autoCompressionRunningProvider = StreamProvider<bool>((ref) {
  final bridge = ref.watch(rustBridgeServiceProvider);
  return bridge.watchAutoCompressionStatus();
});

final schedulerStateProvider = StreamProvider.autoDispose<SchedulerState>((
  ref,
) {
  final bridge = ref.watch(rustBridgeServiceProvider);
  return bridge.watchSchedulerState();
});
