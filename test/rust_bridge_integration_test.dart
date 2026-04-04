import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:pressplay/models/compression_algorithm.dart';
import 'package:pressplay/models/game_info.dart';
import 'package:pressplay/services/rust_bridge_service.dart';
import 'package:pressplay/src/rust/frb_generated.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skipReason = _nativeBridgeSkipReason();

  setUpAll(() async {
    if (skipReason != null) {
      return;
    }

    await _initRustBridgeForTest();
    RustBridgeService.instance.initApp();
  });

  tearDown(() {
    if (skipReason != null) {
      return;
    }

    RustBridgeService.instance.cancelCompression();
  });

  tearDownAll(() async {
    if (skipReason != null) {
      return;
    }

    await RustBridgeService.instance.shutdownApp();
  });

  test(
    'real bridge request-response maps application folder metadata',
    () async {
      final temp = await io.Directory.systemTemp.createTemp(
        'pressplay-bridge-app-',
      );
      addTearDown(() => temp.delete(recursive: true));

      final appDir = io.Directory('${temp.path}\\Toolbox');
      await appDir.create(recursive: true);
      await io.File(
        '${appDir.path}\\toolbox.exe',
      ).writeAsBytes(List<int>.filled(64 * 1024, 7));
      await io.File(
        '${appDir.path}\\payload.bin',
      ).writeAsBytes(List<int>.filled(512 * 1024, 3));

      final app = await RustBridgeService.instance.addApplicationFolder(
        '${appDir.path}\\toolbox.exe',
        name: 'Toolbox',
      );

      expect(app.name, 'Toolbox');
      expect(app.platform, Platform.application);
      expect(app.path, appDir.path);
      expect(app.sizeBytes, greaterThan(0));
    },
    skip: skipReason,
  );

  test(
    'real bridge stream returns completion snapshot for empty folder compression',
    () async {
      final temp = await io.Directory.systemTemp.createTemp(
        'pressplay-bridge-compress-',
      );
      addTearDown(() => temp.delete(recursive: true));

      final progress = await RustBridgeService.instance
          .compressGame(
            gamePath: temp.path,
            gameName: 'Empty Integration Folder',
            algorithm: CompressionAlgorithm.xpress4k,
          )
          .toList();

      expect(progress, isNotEmpty);
      final last = progress.last;
      expect(last.gameName, 'Empty Integration Folder');
      expect(last.isComplete, isTrue);
      expect(last.filesTotal, 0);
      expect(last.filesProcessed, 0);
      expect(last.bytesSaved, 0);
      expect(RustBridgeService.instance.getCompressionProgress(), isNull);
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

String? _nativeBridgeSkipReason() {
  if (!io.Platform.isWindows) {
    return 'Windows-only native bridge integration test';
  }

  for (final candidate in _rustLibraryCandidates()) {
    if (io.File(candidate).existsSync()) {
      return null;
    }
  }

  return 'Rust DLL not found. Build native artifacts before running this test.';
}

Future<void> _initRustBridgeForTest() async {
  Object? lastError;

  for (final candidate in _rustLibraryCandidates()) {
    if (!io.File(candidate).existsSync()) {
      continue;
    }

    try {
      await RustLib.init(externalLibrary: ExternalLibrary.open(candidate));
      return;
    } catch (error) {
      lastError = error;
      _safeDisposeRustLib();
    }
  }

  throw StateError(
    'Failed to initialize Rust bridge for tests. Last error: $lastError',
  );
}

List<String> _rustLibraryCandidates() {
  final cwd = io.Directory.current.path;
  return <String>[
    '$cwd\\rust\\target\\debug\\pressplay_core.dll',
    '$cwd\\rust\\target\\release\\pressplay_core.dll',
  ];
}

void _safeDisposeRustLib() {
  try {
    RustLib.dispose();
  } catch (_) {
    // Ignore dispose failures when init never completed.
  }
}
