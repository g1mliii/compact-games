import 'dart:io';

import 'package:compact_games/services/update_installer_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDirectory;
  late Directory updateDirectory;
  late UpdateInstallerCache cache;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'compact-games-update-cache-',
    );
    updateDirectory = Directory(p.join(tempDirectory.path, 'updates'));
    await updateDirectory.create();
    cache = UpdateInstallerCache(
      directoryResolver: () async => updateDirectory,
    );
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test(
    'deletes stale installers while preserving the current download',
    () async {
      final stale = File(
        p.join(updateDirectory.path, 'CompactGames-Setup-0.2.3.exe'),
      );
      final current = File(
        p.join(updateDirectory.path, 'CompactGames-Setup-0.2.4.exe'),
      );
      final unrelated = File(p.join(updateDirectory.path, 'notes.txt'));
      await stale.writeAsString('stale');
      await current.writeAsString('current');
      await unrelated.writeAsString('keep');

      final deleted = await cache.deleteStaleInstallers(keepVersion: '0.2.4');

      expect(deleted, 1);
      expect(await stale.exists(), isFalse);
      expect(await current.exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
    },
  );

  test('keeps the installer for a version that is still current', () async {
    final superseded = File(
      p.join(updateDirectory.path, 'CompactGames-Setup-0.2.4.exe'),
    );
    final current = File(
      p.join(updateDirectory.path, 'CompactGames-Setup-0.2.5.exe'),
    );
    await superseded.writeAsString('superseded');
    await current.writeAsString('current');

    final deleted = await cache.deleteStaleInstallers(keepVersion: '0.2.5');

    expect(deleted, 1);
    expect(await superseded.exists(), isFalse);
    expect(await current.exists(), isTrue);
    expect(await cache.findVerifiedInstaller('0.2.5'), current.path);
    expect(await cache.findVerifiedInstaller('0.2.4'), isNull);
  });

  test('resolves the download path for a version', () async {
    expect(
      await cache.installerPathFor('0.2.5'),
      p.join(updateDirectory.path, 'CompactGames-Setup-0.2.5.exe'),
    );
  });

  test(
    'deletes interrupted downloads but never follows directory links',
    () async {
      final interrupted = File(
        p.join(updateDirectory.path, 'CompactGames-Setup-0.2.5.tmp'),
      );
      final lookalikeDirectory = Directory(
        p.join(updateDirectory.path, 'CompactGames-Setup-0.2.2.exe'),
      );
      await interrupted.writeAsString('partial');
      await lookalikeDirectory.create();

      final deleted = await cache.deleteStaleInstallers();

      expect(deleted, 1);
      expect(await interrupted.exists(), isFalse);
      expect(await lookalikeDirectory.exists(), isTrue);
    },
  );
}
