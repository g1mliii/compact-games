import 'dart:io' as io;

import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/services/game_launch_target_store.dart';
import 'package:compact_games/services/platform_shell_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Steam launch uses the app protocol without requesting an executable',
    () async {
      final shell = _RecordingPlatformShellService();
      final game = GameInfo(
        name: 'Steam Test',
        path: r'C:\Games\steam_test',
        platform: Platform.steam,
        sizeBytes: 1,
        steamAppId: 12345,
      );

      final result = await shell.launchGame(game);

      expect(result, GameLaunchResult.requested);
      expect(shell.lastUri, 'steam://rungameid/12345');
      expect(shell.lastExecutable, isNull);
      expect(shell.pickExecutableCalls, 0);
    },
  );

  test(
    'folder launch asks for an executable and remembers the confirmed target',
    () async {
      final fixture = await _ExecutableFixture.create();
      addTearDown(fixture.dispose);
      final store = _MemoryGameLaunchTargetStore();
      final shell = _RecordingPlatformShellService(
        launchTargetStore: store,
        selectedExecutable: fixture.executable.path,
      );
      final game = GameInfo(
        name: 'Folder Test',
        path: fixture.directory.path,
        platform: Platform.custom,
        sizeBytes: 1,
      );

      final firstResult = await shell.launchGame(game);
      final secondResult = await shell.launchGame(game);

      expect(firstResult, GameLaunchResult.requested);
      expect(secondResult, GameLaunchResult.requested);
      expect(shell.pickExecutableCalls, 1);
      expect(shell.lastExecutable, fixture.executable.path);
      expect(await store.read(game.path), fixture.executable.path);
    },
  );

  test('direct executable imports launch without opening the picker', () async {
    final fixture = await _ExecutableFixture.create();
    addTearDown(fixture.dispose);
    final shell = _RecordingPlatformShellService();
    final game = GameInfo(
      name: 'Direct Test',
      path: fixture.executable.path,
      platform: Platform.custom,
      sizeBytes: 1,
    );

    final result = await shell.launchGame(game);

    expect(result, GameLaunchResult.requested);
    expect(shell.pickExecutableCalls, 0);
    expect(shell.lastExecutable, fixture.executable.path);
  });

  test('cancelled executable selection does not start a process', () async {
    final fixture = await _ExecutableFixture.create();
    addTearDown(fixture.dispose);
    final shell = _RecordingPlatformShellService();
    final game = GameInfo(
      name: 'Cancelled Test',
      path: fixture.directory.path,
      platform: Platform.custom,
      sizeBytes: 1,
    );

    final result = await shell.launchGame(game);

    expect(result, GameLaunchResult.selectionCancelled);
    expect(shell.pickExecutableCalls, 1);
    expect(shell.lastExecutable, isNull);
  });

  test(
    'an unavailable picker reports failure instead of cancellation',
    () async {
      final fixture = await _ExecutableFixture.create();
      addTearDown(fixture.dispose);
      final shell = _RecordingPlatformShellService(pickerUnavailable: true);
      final game = GameInfo(
        name: 'No Picker Test',
        path: fixture.directory.path,
        platform: Platform.custom,
        sizeBytes: 1,
      );

      final result = await shell.launchGame(game);

      expect(result, GameLaunchResult.failed);
      expect(shell.lastExecutable, isNull);
    },
  );

  test('a selected shortcut is accepted and remembered', () async {
    final fixture = await _ExecutableFixture.create();
    addTearDown(fixture.dispose);
    final store = _MemoryGameLaunchTargetStore();
    final shell = _RecordingPlatformShellService(
      launchTargetStore: store,
      selectedExecutable: fixture.shortcut.path,
    );
    final game = GameInfo(
      name: 'Shortcut Test',
      path: fixture.directory.path,
      platform: Platform.custom,
      sizeBytes: 1,
    );

    final result = await shell.launchGame(game);

    expect(result, GameLaunchResult.requested);
    expect(shell.lastExecutable, fixture.shortcut.path);
    expect(await store.read(game.path), fixture.shortcut.path);
  });

  test('stale remembered target is removed before prompting again', () async {
    final fixture = await _ExecutableFixture.create();
    addTearDown(fixture.dispose);
    final store = _MemoryGameLaunchTargetStore();
    await store.write(fixture.directory.path, fixture.missingExecutable.path);
    final shell = _RecordingPlatformShellService(
      launchTargetStore: store,
      selectedExecutable: fixture.executable.path,
    );
    final game = GameInfo(
      name: 'Moved Test',
      path: fixture.directory.path,
      platform: Platform.custom,
      sizeBytes: 1,
    );

    final result = await shell.launchGame(game);

    expect(result, GameLaunchResult.requested);
    expect(shell.pickExecutableCalls, 1);
    expect(await store.read(game.path), fixture.executable.path);
  });
}

class _RecordingPlatformShellService extends PlatformShellService {
  _RecordingPlatformShellService({
    GameLaunchTargetStore? launchTargetStore,
    this.selectedExecutable,
    this.pickerUnavailable = false,
  }) : super(
         launchTargetStore: launchTargetStore ?? _MemoryGameLaunchTargetStore(),
       );

  final String? selectedExecutable;
  final bool pickerUnavailable;
  String? lastUri;
  String? lastExecutable;
  int pickExecutableCalls = 0;

  @override
  Future<bool> launchUri(String uri) async {
    lastUri = uri;
    return true;
  }

  @override
  Future<String?> pickGameExecutable() async {
    pickExecutableCalls += 1;
    if (pickerUnavailable) {
      throw const PathPickerUnavailableException('test');
    }
    return selectedExecutable;
  }

  @override
  Future<bool> launchExecutable(String executablePath) async {
    lastExecutable = executablePath;
    return true;
  }
}

class _MemoryGameLaunchTargetStore extends GameLaunchTargetStore {
  final Map<String, String> _targets = <String, String>{};

  @override
  Future<String?> read(String gamePath) async => _targets[gamePath];

  @override
  Future<void> write(String gamePath, String executablePath) async {
    _targets[gamePath] = executablePath;
  }

  @override
  Future<void> remove(String gamePath) async {
    _targets.remove(gamePath);
  }
}

class _ExecutableFixture {
  _ExecutableFixture({
    required this.directory,
    required this.executable,
    required this.shortcut,
    required this.missingExecutable,
  });

  final io.Directory directory;
  final io.File executable;
  final io.File shortcut;
  final io.File missingExecutable;

  static Future<_ExecutableFixture> create() async {
    final directory = await io.Directory.systemTemp.createTemp(
      'compact_games_launch_test_',
    );
    final executable = io.File(
      '${directory.path}${io.Platform.pathSeparator}game.exe',
    );
    await executable.writeAsBytes(const <int>[0]);
    final shortcut = io.File(
      '${directory.path}${io.Platform.pathSeparator}game.lnk',
    );
    await shortcut.writeAsBytes(const <int>[0]);
    return _ExecutableFixture(
      directory: directory,
      executable: executable,
      shortcut: shortcut,
      missingExecutable: io.File(
        '${directory.path}${io.Platform.pathSeparator}missing.exe',
      ),
    );
  }

  Future<void> dispose() => directory.delete(recursive: true);
}
