import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:compact_games/providers/settings/settings_persistence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads Compact Games settings from storage', () async {
    SharedPreferences.setMockInitialValues({
      'compact_games_settings': jsonEncode({
        'schemaVersion': 5,
        'autoCompress': true,
        'customFolders': ['D:/Games'],
      }),
    });

    const persistence = SettingsPersistence();
    final loaded = await persistence.load();
    final prefs = await SharedPreferences.getInstance();

    expect(loaded.autoCompress, isTrue);
    expect(loaded.customFolders, ['D:/Games']);
    expect(prefs.getString('compact_games_settings'), isNotNull);
  });
}
