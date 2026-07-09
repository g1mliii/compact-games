import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/launch_at_startup_service.dart';

final launchAtStartupServiceProvider = Provider<LaunchAtStartupService>((ref) {
  return const LaunchAtStartupService();
});

final launchAtStartupProvider =
    AsyncNotifierProvider<LaunchAtStartupNotifier, bool>(
      LaunchAtStartupNotifier.new,
    );

class LaunchAtStartupNotifier extends AsyncNotifier<bool> {
  Future<void> _writeQueue = Future<void>.value();
  int _requestGeneration = 0;

  @override
  Future<bool> build() {
    return ref.read(launchAtStartupServiceProvider).isEnabled();
  }

  Future<void> setEnabled(bool enabled) async {
    // Optimistic update: flip the switch immediately and keep the prior value
    // if the registry write fails. Avoids a visible flicker (loading → false →
    // true) while reg.exe runs.
    final requestGeneration = ++_requestGeneration;
    state = AsyncValue.data(enabled);

    final write = _writeQueue.then(
      (_) => ref.read(launchAtStartupServiceProvider).setEnabled(enabled),
    );
    _writeQueue = write.catchError((Object _) {});

    try {
      await write;
      if (requestGeneration == _requestGeneration) {
        state = AsyncValue.data(enabled);
      }
    } catch (e, st) {
      if (requestGeneration != _requestGeneration) {
        return;
      }
      state = AsyncValue<bool>.error(e, st);
    }
  }
}
