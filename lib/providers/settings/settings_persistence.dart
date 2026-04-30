import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/app_settings.dart';

const _settingsKey = 'compact_games_settings';
const _steamGridDbApiKeyKey = 'compact_games_steamgriddb_api_key';

/// Read/write AppSettings to SharedPreferences.
class SettingsPersistence {
  const SettingsPersistence();
  static Future<SharedPreferences> get _prefsFuture =>
      SharedPreferences.getInstance();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  Future<AppSettings> load() async {
    final (prefs, secureApiKey) = await (_prefsFuture, _readSecureApiKey()).wait;
    final loaded = _loadSettingsFromPrefs(prefs);
    final settings = loaded.settings;

    if (secureApiKey != null) {
      final migratedMode = loaded.hasCoverArtProviderMode
          ? settings.coverArtProviderMode
          : CoverArtProviderMode.userKey;
      final sanitized = settings
          .copyWith(coverArtProviderMode: migratedMode)
          .copyWith(steamGridDbApiKey: () => null)
          .validated();
      if (settings.steamGridDbApiKey != null ||
          sanitized.schemaVersion != loaded.schemaVersion ||
          !loaded.hasCoverArtProviderMode ||
          sanitized.coverArtProviderMode != settings.coverArtProviderMode) {
        await _persistSettingsBestEffort(prefs, sanitized);
      }
      return sanitized
          .copyWith(steamGridDbApiKey: () => secureApiKey)
          .validated();
    }

    final legacyApiKey = settings.steamGridDbApiKey;
    if (legacyApiKey != null) {
      try {
        await _writeSecureApiKey(legacyApiKey);
      } catch (_) {
        // Keep legacy in-memory value if secure migration fails.
        return settings.validated();
      }

      final migrated = settings
          .copyWith(steamGridDbApiKey: () => null)
          .validated();
      await _persistSettingsBestEffort(prefs, migrated);
      return migrated
          .copyWith(steamGridDbApiKey: () => legacyApiKey)
          .validated();
    }

    return settings.validated();
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await _prefsFuture;
    final sanitized = settings
        .copyWith(steamGridDbApiKey: () => null)
        .validated();
    await (
      _writeSecureApiKey(settings.steamGridDbApiKey),
      _writeSettingsToPrefs(prefs, sanitized),
    ).wait;
  }

  _LoadedSettings _loadSettingsFromPrefs(SharedPreferences prefs) {
    final json = prefs.getString(_settingsKey);
    if (json != null) {
      return _decodeSettings(json);
    }
    return const _LoadedSettings(
      settings: AppSettings(),
      schemaVersion: AppSettings.currentSchemaVersion,
      hasCoverArtProviderMode: false,
    );
  }

  _LoadedSettings _decodeSettings(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final schemaVersion = map['schemaVersion'] as int? ?? 1;
      return _LoadedSettings(
        settings: AppSettings.fromJson(map),
        schemaVersion: schemaVersion <= 0 ? 1 : schemaVersion,
        hasCoverArtProviderMode: map.containsKey('coverArtProviderMode'),
      );
    } catch (_) {
      return const _LoadedSettings(
        settings: AppSettings(),
        schemaVersion: AppSettings.currentSchemaVersion,
        hasCoverArtProviderMode: false,
      );
    }
  }

  Future<void> _writeSettingsToPrefs(
    SharedPreferences prefs,
    AppSettings settings,
  ) async {
    final json = jsonEncode(settings.toJson());
    await prefs.setString(_settingsKey, json);
  }

  Future<void> _persistSettingsBestEffort(
    SharedPreferences prefs,
    AppSettings settings,
  ) async {
    try {
      await _writeSettingsToPrefs(prefs, settings);
    } catch (_) {
      // Keep runtime settings usable; scrub persisted plaintext on the next load.
    }
  }

  Future<String?> _readSecureApiKey() async {
    try {
      final value = await _secureStorage.read(key: _steamGridDbApiKeyKey);
      return _normalizeApiKey(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSecureApiKey(String? apiKey) async {
    final normalized = _normalizeApiKey(apiKey);
    if (normalized == null) {
      await _secureStorage.delete(key: _steamGridDbApiKeyKey);
      return;
    }
    await _secureStorage.write(key: _steamGridDbApiKeyKey, value: normalized);
  }

  String? _normalizeApiKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

class _LoadedSettings {
  const _LoadedSettings({
    required this.settings,
    required this.schemaVersion,
    required this.hasCoverArtProviderMode,
  });

  final AppSettings settings;
  final int schemaVersion;
  final bool hasCoverArtProviderMode;
}
