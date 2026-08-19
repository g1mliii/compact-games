import 'dart:io';

import 'package:compact_games/services/packaged_app_logo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Writes a manifest and its asset files into a temporary package layout.
Future<Directory> _package({
  required String manifest,
  Map<String, int> assets = const <String, int>{},
  String manifestName = 'appxmanifest.xml',
  bool inContentFolder = true,
}) async {
  final root = await Directory.systemTemp.createTemp('packaged_app_logo');
  addTearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  final payload = inContentFolder
      ? Directory(p.join(root.path, 'Content'))
      : root;
  await payload.create(recursive: true);
  await File(p.join(payload.path, manifestName)).writeAsString(manifest);

  for (final entry in assets.entries) {
    final file = File(
      p.join(payload.path, entry.key.replaceAll(r'\', p.separator)),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(entry.value, 7));
  }
  return root;
}

const String _minecraftish = '''
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10">
  <Properties>
    <DisplayName>Minecraft for Windows</DisplayName>
    <Logo>StoreLogo.png</Logo>
  </Properties>
  <Applications>
    <Application Id="App">
      <uap:VisualElements Square150x150Logo="Logo.png" Square44x44Logo="SmallLogo.png" />
    </Application>
  </Applications>
</Package>
''';

void main() {
  group('findPackagedAppLogo', () {
    test('prefers the largest tile the manifest declares', () async {
      final root = await _package(
        manifest: _minecraftish,
        assets: <String, int>{
          'StoreLogo.png': 930,
          'Logo.png': 1274,
          'SmallLogo.png': 698,
        },
      );

      final logo = await findPackagedAppLogo(root.path);

      expect(logo, isNotNull);
      expect(p.basename(logo!.path), 'Logo.png');
    });

    test('finds the scale variant a package actually ships', () async {
      // Manifests name `Assets\Logo.png` while the installed package carries
      // only `Assets\Logo.scale-200.png`, so resolving the literal name finds
      // nothing for most packages.
      final root = await _package(
        manifest: '''
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10">
  <Applications><Application>
    <uap:VisualElements Square150x150Logo="Assets\\Logo.png" />
  </Application></Applications>
</Package>
''',
        assets: <String, int>{
          r'Assets\Logo.scale-100.png': 400,
          r'Assets\Logo.scale-200.png': 4000,
        },
      );

      final logo = await findPackagedAppLogo(root.path);

      expect(p.basename(logo!.path), 'Logo.scale-200.png');
    });

    test('reads a manifest at the package root as well', () async {
      final root = await _package(
        manifest: _minecraftish,
        assets: <String, int>{'Logo.png': 500},
        inContentFolder: false,
      );

      expect(await findPackagedAppLogo(root.path), isNotNull);
    });

    test('falls back to the store logo when no tile is declared', () async {
      final root = await _package(
        manifest: '''
<?xml version="1.0" encoding="utf-8"?>
<Package><Properties><Logo>StoreLogo.png</Logo></Properties></Package>
''',
        assets: <String, int>{'StoreLogo.png': 900},
      );

      final logo = await findPackagedAppLogo(root.path);

      expect(p.basename(logo!.path), 'StoreLogo.png');
    });

    test('a folder that is not a package yields nothing', () async {
      final root = await Directory.systemTemp.createTemp('plain_game');
      addTearDown(() => root.delete(recursive: true));

      expect(await findPackagedAppLogo(root.path), isNull);
    });

    test('a declared asset that was never installed yields nothing', () async {
      final root = await _package(manifest: _minecraftish);

      expect(await findPackagedAppLogo(root.path), isNull);
    });

    test('malformed xml is not a crash', () async {
      final root = await _package(
        manifest: '<Package><Properties><Logo>oops',
        assets: <String, int>{'Logo.png': 500},
      );

      expect(await findPackagedAppLogo(root.path), isNull);
    });
  });
}
