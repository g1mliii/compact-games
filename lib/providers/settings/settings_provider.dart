import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_settings.dart';
import '../../models/compression_algorithm.dart';
import 'settings_persistence.dart';
import 'settings_state.dart';

final settingsPersistenceProvider = Provider<SettingsPersistence>((ref) {
  return const SettingsPersistence();
});

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  Timer? _debounceTimer;

  @override
  Future<SettingsState> build() async {
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });
    return _loadSettings();
  }

  Future<SettingsState> _loadSettings() async {
    try {
      final persistence = ref.read(settingsPersistenceProvider);
      final settings = await persistence.load();
      return SettingsState(settings: settings.validated(), isLoaded: true);
    } catch (_) {
      return const SettingsState(
        settings: AppSettings(),
        isLoaded: true,
        error: 'Settings corrupted, using defaults.',
      );
    }
  }

  void updateAlgorithm(CompressionAlgorithm algorithm) {
    _updateSetting((s) => s.copyWith(algorithm: algorithm));
  }

  void toggleAutoCompress() {
    final current = state.valueOrNull?.settings;
    if (current == null) return;
    _updateSetting((s) => s.copyWith(autoCompress: !s.autoCompress));
  }

  void setAutoCompress(bool enabled) {
    _updateSetting((s) => s.copyWith(autoCompress: enabled));
  }

  void setCpuThreshold(double percent) {
    _updateSetting((s) => s.copyWith(cpuThreshold: percent));
  }

  void setIdleDuration(int minutes) {
    _updateSetting((s) => s.copyWith(idleDurationMinutes: minutes));
  }

  void addCustomFolder(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return;
    }
    _updateSetting(
      (s) {
        if (s.customFolders.contains(normalized)) {
          return s;
        }
        return s.copyWith(customFolders: [...s.customFolders, normalized]);
      },
    );
  }

  void removeCustomFolder(String path) {
    _updateSetting(
      (s) => s.copyWith(
        customFolders: s.customFolders.where((f) => f != path).toList(),
      ),
    );
  }

  void toggleGameExclusion(String gamePath) {
    final current = state.valueOrNull?.settings;
    if (current == null) return;
    final excluded = List<String>.from(current.excludedPaths);
    if (excluded.contains(gamePath)) {
      excluded.remove(gamePath);
    } else {
      excluded.add(gamePath);
    }
    _updateSetting((s) => s.copyWith(excludedPaths: excluded));
  }

  void setNotificationsEnabled(bool enabled) {
    _updateSetting((s) => s.copyWith(notificationsEnabled: enabled));
  }

  void setThemeVariant(String variant) {
    _updateSetting((s) => s.copyWith(themeVariant: variant));
  }

  void setDirectStorageOverrideEnabled(bool enabled) {
    _updateSetting((s) => s.copyWith(directStorageOverrideEnabled: enabled));
  }

  void setSteamGridDbApiKey(String? key) {
    _updateSetting((s) => s.copyWith(steamGridDbApiKey: () => key));
  }

  void setInventoryAdvancedScanEnabled(bool enabled) {
    _updateSetting((s) => s.copyWith(inventoryAdvancedScanEnabled: enabled));
  }

  void _updateSetting(AppSettings Function(AppSettings) updater) {
    final current = state.valueOrNull;
    if (current == null) return;
    final newSettings = updater(current.settings).validated();
    state = AsyncValue.data(current.copyWith(
      settings: newSettings,
      error: () => null,
    ));
    _debounceSave(newSettings);
  }

  void _debounceSave(AppSettings settings) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final persistence = ref.read(settingsPersistenceProvider);
        await persistence.save(settings);
      } catch (_) {
        // Settings are in memory; save failure is non-fatal
      }
    });
  }
}
