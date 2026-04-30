import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_locale.dart';
import '../../models/app_settings.dart';
import '../../models/compression_algorithm.dart';
import '../games/manual_game_import.dart';
import 'settings_persistence.dart';
import 'settings_state.dart';

final settingsPersistenceProvider = Provider<SettingsPersistence>((ref) {
  return const SettingsPersistence();
});

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, SettingsState>(
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
    final normalizedInput = path.trim();
    if (normalizedInput.isEmpty) {
      return;
    }
    final resolved = resolveManualImportTarget(normalizedInput);
    final normalized = resolved.folderPath;
    final normalizedKey = manualImportPathKey(normalized);
    _updateSetting((s) {
      final alreadyExists = s.customFolders.any(
        (existing) => manualImportPathKey(existing) == normalizedKey,
      );
      if (alreadyExists) {
        return s;
      }
      return s.copyWith(customFolders: [...s.customFolders, normalized]);
    });
  }

  void removeCustomFolder(String path) {
    final normalizedKey = manualImportPathKey(path);
    _updateSetting(
      (s) => s.copyWith(
        customFolders: s.customFolders
            .where((folder) => manualImportPathKey(folder) != normalizedKey)
            .toList(),
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

  void setIoParallelismOverride(int? value) {
    _updateSetting((s) => s.copyWith(ioParallelismOverride: () => value));
  }

  void setSteamGridDbApiKey(String? key) {
    _updateSetting((s) => s.copyWith(steamGridDbApiKey: () => key));
  }

  void setCoverArtProviderMode(CoverArtProviderMode mode) {
    _updateSetting((s) => s.copyWith(coverArtProviderMode: mode));
  }

  void setInventoryAdvancedScanEnabled(bool enabled) {
    _updateSetting((s) => s.copyWith(inventoryAdvancedScanEnabled: enabled));
  }

  void setMinimizeToTray(bool enabled) {
    _updateSetting((s) => s.copyWith(minimizeToTray: enabled));
  }

  void setHomeViewMode(HomeViewMode mode) {
    _updateSetting((s) => s.copyWith(homeViewMode: mode));
  }

  void setLocaleTag(String? localeTag) {
    final canonicalTag = canonicalLocaleTag(localeTag);
    _updateSetting((s) => s.copyWith(localeTag: () => canonicalTag));
  }

  void setAutoCheckUpdates(bool enabled) {
    _updateSetting((s) => s.copyWith(autoCheckUpdates: enabled));
  }

  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;

    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    await _saveSettings(current.settings);
  }

  void _updateSetting(AppSettings Function(AppSettings) updater) {
    final current = state.valueOrNull;
    if (current == null) return;
    final newSettings = updater(current.settings).validated();
    if (_settingsEqual(current.settings, newSettings)) {
      return;
    }
    state = AsyncValue.data(
      current.copyWith(settings: newSettings, error: () => null),
    );
    _debounceSave(newSettings);
  }

  void _debounceSave(AppSettings settings) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      await _saveSettings(settings);
    });
  }

  Future<void> _saveSettings(AppSettings settings) async {
    try {
      final persistence = ref.read(settingsPersistenceProvider);
      await persistence.save(settings);
    } catch (_) {
      // Settings are in memory; save failure is non-fatal.
    }
  }
}

bool _settingsEqual(AppSettings a, AppSettings b) {
  return a.schemaVersion == b.schemaVersion &&
      a.algorithm == b.algorithm &&
      a.autoCompress == b.autoCompress &&
      a.cpuThreshold == b.cpuThreshold &&
      a.idleDurationMinutes == b.idleDurationMinutes &&
      a.cooldownMinutes == b.cooldownMinutes &&
      listEquals(a.customFolders, b.customFolders) &&
      listEquals(a.excludedPaths, b.excludedPaths) &&
      a.notificationsEnabled == b.notificationsEnabled &&
      a.themeVariant == b.themeVariant &&
      a.directStorageOverrideEnabled == b.directStorageOverrideEnabled &&
      a.ioParallelismOverride == b.ioParallelismOverride &&
      a.steamGridDbApiKey == b.steamGridDbApiKey &&
      a.coverArtProviderMode == b.coverArtProviderMode &&
      a.inventoryAdvancedScanEnabled == b.inventoryAdvancedScanEnabled &&
      a.minimizeToTray == b.minimizeToTray &&
      a.homeViewMode == b.homeViewMode &&
      a.localeTag == b.localeTag &&
      a.autoCheckUpdates == b.autoCheckUpdates;
}
