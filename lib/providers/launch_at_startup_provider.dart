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
  @override
  Future<bool> build() {
    return ref.read(launchAtStartupServiceProvider).isEnabled();
  }

  Future<void> setEnabled(bool enabled) async {
    // Optimistic update: flip the switch immediately and keep the prior value
    // if the registry write fails. Avoids a visible flicker (loading → false →
    // true) while reg.exe runs.
    final previous = state.valueOrNull ?? !enabled;
    state = AsyncValue.data(enabled);
    try {
      await ref.read(launchAtStartupServiceProvider).setEnabled(enabled);
    } catch (e, st) {
      state = AsyncValue<bool>.error(
        e,
        st,
      ).copyWithPrevious(AsyncValue<bool>.data(previous));
    }
  }
}
