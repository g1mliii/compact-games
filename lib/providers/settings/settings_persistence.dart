import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/app_settings.dart';

const _settingsKey = 'pressplay_settings';

/// Read/write AppSettings to SharedPreferences.
class SettingsPersistence {
  const SettingsPersistence();
  static final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  Future<AppSettings> load() async {
    final prefs = await _prefsFuture;
    final json = prefs.getString(_settingsKey);
    if (json == null) return const AppSettings();
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return AppSettings.fromJson(map);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await _prefsFuture;
    final json = jsonEncode(settings.toJson());
    await prefs.setString(_settingsKey, json);
  }
}
