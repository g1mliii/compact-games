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
    state = const AsyncValue.loading();
    try {
      await ref.read(launchAtStartupServiceProvider).setEnabled(enabled);
      state = AsyncValue.data(enabled);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
