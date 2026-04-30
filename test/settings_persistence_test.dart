import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:compact_games/models/app_settings.dart';
import 'package:compact_games/providers/settings/settings_persistence.dart';
import 'package:compact_games/providers/settings/settings_provider.dart';

const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'secure-storage legacy SteamGridDB key migrates to user-key mode',
    () async {
      final secureValues = <String, String>{
        'compact_games_steamgriddb_api_key': 'secure-demo-key',
      };
      _installSecureStorageMock(secureValues);
      SharedPreferences.setMockInitialValues({
        'compact_games_settings': jsonEncode({
          'schemaVersion': 5,
          'autoCompress': true,
        }),
      });

      const persistence = SettingsPersistence();
      final loaded = await persistence.load();
      final prefs = await SharedPreferences.getInstance();
      final persisted =
          jsonDecode(prefs.getString('compact_games_settings')!)
              as Map<String, dynamic>;

      expect(loaded.steamGridDbApiKey, 'secure-demo-key');
      expect(loaded.coverArtProviderMode, CoverArtProviderMode.userKey);
      expect(persisted['coverArtProviderMode'], 'userKey');
      expect(persisted, isNot(contains('steamGridDbApiKey')));
    },
  );

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
    expect(loaded.coverArtProviderMode, CoverArtProviderMode.bundledProxy);
    expect(loaded.schemaVersion, AppSettings.currentSchemaVersion);
    expect(prefs.getString('compact_games_settings'), isNotNull);
  });

  test('AppSettings defaults new installs to bundled cover proxy', () {
    const settings = AppSettings();

    expect(settings.coverArtProviderMode, CoverArtProviderMode.bundledProxy);
    expect(settings.toJson(), isNot(contains('steamGridDbApiKey')));
  });

  test('AppSettings migrates legacy SteamGridDB keys to user-key mode', () {
    final settings = AppSettings.fromJson({
      'schemaVersion': 5,
      'steamGridDbApiKey': ' compact-games-demo-key ',
    });

    expect(settings.steamGridDbApiKey, 'compact-games-demo-key');
    expect(settings.coverArtProviderMode, CoverArtProviderMode.userKey);
    expect(settings.schemaVersion, AppSettings.currentSchemaVersion);
  });

  test('AppSettings preserves explicit cover-art provider mode', () {
    final settings = AppSettings.fromJson({
      'schemaVersion': AppSettings.currentSchemaVersion,
      'coverArtProviderMode': 'userKey',
    });

    expect(settings.coverArtProviderMode, CoverArtProviderMode.userKey);
    expect(
      AppSettings.fromJson(settings.toJson()).coverArtProviderMode,
      CoverArtProviderMode.userKey,
    );
  });

  test('settings provider persists cover-art provider mode changes', () async {
    final persistence = _MemorySettingsPersistence();
    final container = ProviderContainer(
      overrides: [settingsPersistenceProvider.overrideWithValue(persistence)],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    container
        .read(settingsProvider.notifier)
        .setCoverArtProviderMode(CoverArtProviderMode.userKey);
    await container.read(settingsProvider.notifier).flush();

    expect(
      persistence.savedSettings?.coverArtProviderMode,
      CoverArtProviderMode.userKey,
    );
  });
}

void _installSecureStorageMock(Map<String, String> values) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
        final arguments =
            (call.arguments as Map<Object?, Object?>?) ?? const {};
        final key = arguments['key'] as String?;
        switch (call.method) {
          case 'read':
            return key == null ? null : values[key];
          case 'write':
            if (key != null) {
              values[key] = arguments['value'] as String;
            }
            return null;
          case 'delete':
            if (key != null) {
              values.remove(key);
            }
            return null;
          case 'containsKey':
            return key != null && values.containsKey(key);
          case 'readAll':
            return Map<String, String>.from(values);
          case 'deleteAll':
            values.clear();
            return null;
        }
        throw PlatformException(
          code: 'unsupported',
          message: 'Unsupported secure storage method ${call.method}',
        );
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });
}

class _MemorySettingsPersistence implements SettingsPersistence {
  AppSettings _current = const AppSettings();
  AppSettings? savedSettings;

  @override
  Future<AppSettings> load() async => _current;

  @override
  Future<void> save(AppSettings settings) async {
    savedSettings = settings;
    _current = settings;
  }
}
