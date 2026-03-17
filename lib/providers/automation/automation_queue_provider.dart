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
  for (final job in queue) {
    if (job.status == AutomationJobStatus.compressing) {
      return job;
    }
  }
  return null;
});

final pendingAutomationCountProvider = Provider.autoDispose<int>((ref) {
  final queue = ref.watch(automationQueueProvider).valueOrNull;
  if (queue == null) return 0;
  var pendingCount = 0;
  for (final job in queue) {
    if (job.status == AutomationJobStatus.pending ||
        job.status == AutomationJobStatus.waitingForSettle ||
        job.status == AutomationJobStatus.waitingForIdle) {
      pendingCount += 1;
    }
  }
  return pendingCount;
});
