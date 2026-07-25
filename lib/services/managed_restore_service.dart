import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/managed_restore_plan.dart';
import '../src/rust/api/compression.dart' as rust_compression;

final managedRestoreServiceProvider = Provider<ManagedRestoreService>((ref) {
  return const ManagedRestoreService();
});

final managedRestoreRefreshProvider =
    NotifierProvider<ManagedRestoreRefreshNotifier, int>(
      ManagedRestoreRefreshNotifier.new,
    );

class ManagedRestoreRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void notifyPlanChanged() {
    state += 1;
  }
}

class ManagedRestoreService {
  const ManagedRestoreService();

  Future<ManagedRestorePlan> getPlan() async {
    final plan = await rust_compression.getManagedRestorePlan();
    return ManagedRestorePlan(
      games: plan.games
          .map(
            (game) => ManagedRestoreGame(
              gamePath: game.gamePath,
              gameName: game.gameName,
              drive: game.drive,
              requiredBytes: game.requiredBytes.toInt(),
            ),
          )
          .toList(growable: false),
      drives: plan.drives
          .map(
            (drive) => ManagedRestoreDrive(
              drive: drive.drive,
              requiredBytes: drive.requiredBytes.toInt(),
              availableBytes: drive.availableBytes.toInt(),
            ),
          )
          .toList(growable: false),
    );
  }
}
