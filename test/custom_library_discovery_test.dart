import 'dart:async';

import 'package:compact_games/models/app_settings.dart';
import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/settings/settings_persistence.dart';
import 'package:compact_games/providers/settings/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/noop_rust_bridge_service.dart';

class _Settings extends SettingsPersistence {
  _Settings(this.settings);
  AppSettings settings;
  Completer<void>? loadGate;

  @override
  Future<AppSettings> load() async {
    await loadGate?.future;
    return settings;
  }

  @override
  Future<void> save(AppSettings settings) async => this.settings = settings;
}

GameInfo _game(String path, {Platform platform = Platform.custom}) => GameInfo(
  name: path.split('/').last,
  path: path,
  platform: platform,
  sizeBytes: 1024,
);

class _Bridge extends NoOpRustBridgeService {
  final calls = <({List<String> paths, bool quick, bool refresh})>[];
  final libraries = <String, List<GameInfo>>{};
  Completer<void>? pause;

  @override
  Future<List<GameInfo>> getAllGamesQuick() async => [
    _game('/steam/Game', platform: Platform.steam),
  ];

  @override
  Future<List<GameInfo>> getAllGames() => getAllGamesQuick();

  @override
  Future<List<GameInfo>> refreshAllGames() => getAllGamesQuick();

  @override
  Future<List<GameInfo>> scanCustomLibraryFolders(
    List<String> paths, {
    bool quick = false,
    bool refresh = false,
  }) async {
    calls.add((paths: paths, quick: quick, refresh: refresh));
    final result = [
      for (final root in paths) ...?libraries[root.replaceAll('\\', '/')],
    ];
    await pause?.future;
    return result;
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Discovery did not settle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer create(
    _Bridge bridge,
    List<String> roots, {
    _Settings? persistence,
  }) {
    final container = ProviderContainer(
      overrides: [
        rustBridgeServiceProvider.overrideWithValue(bridge),
        settingsPersistenceProvider.overrideWithValue(
          persistence ??
              _Settings(AppSettings(customFolders: roots, autoCompress: false)),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('slow settings do not hold up platform discovery and saved roots load when ready', () async {
    final gate = Completer<void>();
    final persistence = _Settings(
      const AppSettings(customFolders: ['/Library'], autoCompress: false),
    )..loadGate = gate;
    final bridge = _Bridge()..libraries['/Library'] = [_game('/Library/One')];
    final container = create(bridge, [], persistence: persistence);
    final initial = await container.read(gameListProvider.future);
    expect(initial.games.single.platform, Platform.steam);
    gate.complete();
    await _until(
      () => container.read(gameListProvider).value!.games.length == 2,
    );
  });

  test('saved libraries join quick, full and explicit refresh scans and dedupe launcher games', () async {
    final bridge = _Bridge()
      ..libraries['/Library'] = [
        _game('/Library/One'),
        _game('/Library/Two'),
        _game('/steam/Game'),
      ];
    final container = create(bridge, ['/Library']);
    final initial = await container.read(gameListProvider.future);
    expect(initial.games.length, 3);
    expect(initial.games.first.platform, Platform.steam);
    expect(bridge.calls.first.quick, isTrue);
    await _until(() => bridge.calls.length == 2);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.calls.last.quick, isFalse);

    await container.read(gameListProvider.notifier).refresh();
    expect(bridge.calls.last.refresh, isTrue);
    expect(container.read(gameListProvider).value!.games.length, 3);
  });

  test('adding and removing settings roots updates the open library with automation disabled', () async {
    final bridge = _Bridge()
      ..libraries['/Library'] = [_game('/Library/One'), _game('/Library/Two')];
    final container = create(bridge, []);
    await container.read(gameListProvider.future);
    final settings = container.read(settingsProvider.notifier);
    settings.addCustomFolder('/Library');
    await _until(
      () => container.read(gameListProvider).value!.games.length == 3,
    );
    expect(
      container.read(settingsProvider).value!.settings.autoCompress,
      isFalse,
    );
    settings.removeCustomFolder(
      container.read(settingsProvider).value!.settings.customFolders.single,
    );
    await _until(
      () => container.read(gameListProvider).value!.games.length == 1,
    );
  });

  test(
    'a path changed during a scan cannot publish results from the old root',
    () async {
      final bridge = _Bridge()
        ..libraries['/Old'] = [_game('/Old/One')]
        ..libraries['/New'] = [_game('/New/Two')];
      final container = create(bridge, []);
      await container.read(gameListProvider.future);
      await Future<void>.delayed(Duration.zero);
      final paused = Completer<void>();
      bridge.pause = paused;
      final settings = container.read(settingsProvider.notifier);
      settings.addCustomFolder('/Old');
      await _until(() => bridge.calls.isNotEmpty);
      settings.removeCustomFolder(
        container.read(settingsProvider).value!.settings.customFolders.single,
      );
      settings.addCustomFolder('/New');
      paused.complete();
      await _until(
        () => container
            .read(gameListProvider)
            .value!
            .games
            .any((game) => game.path == '/New/Two'),
      );
      expect(
        container
            .read(gameListProvider)
            .value!
            .games
            .any((game) => game.path == '/Old/One'),
        isFalse,
      );
    },
  );
}
