import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/automation_state.dart';
import '../games/game_list_provider.dart';

final automationQueueProvider = StreamProvider.autoDispose<List<AutomationJob>>(
  (ref) {
    final bridge = ref.watch(rustBridgeServiceProvider);
    return bridge.watchAutomationQueue();
  },
);

final activeAutomationJobProvider = Provider.autoDispose<AutomationJob?>((ref) {
  final queue = ref.watch(automationQueueProvider).valueOrNull;
  if (queue == null || queue.isEmpty) return null;
  try {
    return queue.firstWhere((j) => j.status == AutomationJobStatus.compressing);
  } on StateError {
    return null;
  }
});

final pendingAutomationCountProvider = Provider.autoDispose<int>((ref) {
  final queue = ref.watch(automationQueueProvider).valueOrNull;
  if (queue == null) return 0;
  return queue
      .where(
        (j) =>
            j.status == AutomationJobStatus.pending ||
            j.status == AutomationJobStatus.waitingForSettle ||
            j.status == AutomationJobStatus.waitingForIdle,
      )
      .length;
});
