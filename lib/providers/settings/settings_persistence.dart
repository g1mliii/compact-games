import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/app_settings.dart';

const _settingsKey = 'pressplay_settings';
const _steamGridDbApiKeyKey = 'pressplay_steamgriddb_api_key';

/// Read/write AppSettings to SharedPreferences.
class SettingsPersistence {
  const SettingsPersistence();
  static final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  Future<AppSettings> load() async {
    final prefs = await _prefsFuture;
    final settings = _loadSettingsFromPrefs(prefs);

    final secureApiKey = await _readSecureApiKey();
    if (secureApiKey != null) {
      return settings.copyWith(steamGridDbApiKey: () => secureApiKey).validated();
    }

    final legacyApiKey = settings.steamGridDbApiKey;
    if (legacyApiKey != null) {
      try {
        await _writeSecureApiKey(legacyApiKey);
        final migrated = settings
            .copyWith(steamGridDbApiKey: () => null)
            .validated();
        await _writeSettingsToPrefs(prefs, migrated);
        return settings.validated();
      } catch (_) {
        // Keep legacy in-memory value if secure migration fails.
        return settings.validated();
      }
    }

    return settings.validated();
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await _prefsFuture;
    final sanitized = settings.copyWith(steamGridDbApiKey: () => null).validated();
    await _writeSecureApiKey(settings.steamGridDbApiKey);
    await _writeSettingsToPrefs(prefs, sanitized);
  }

  AppSettings _loadSettingsFromPrefs(SharedPreferences prefs) {
    final json = prefs.getString(_settingsKey);
    if (json == null) {
      return const AppSettings();
    }
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return AppSettings.fromJson(map);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> _writeSettingsToPrefs(
    SharedPreferences prefs,
    AppSettings settings,
  ) async {
    final json = jsonEncode(settings.toJson());
    await prefs.setString(_settingsKey, json);
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
