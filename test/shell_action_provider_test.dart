import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:compact_games/models/compression_algorithm.dart';
import 'package:compact_games/models/compression_progress.dart';
import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/providers/compression/compression_provider.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/shell/shell_action_provider.dart';
import 'package:compact_games/services/shell_launch_args.dart';

import 'support/noop_rust_bridge_service.dart';

void main() {
  test('compress shell action adds target and starts compression', () async {
    final bridge = _ShellActionBridge();
    final container = _container(bridge);
    addTearDown(container.dispose);

    await container
        .read(shellActionExecutorProvider)
        .execute(
          const ShellActionRequest(
            kind: ShellActionKind.compress,
            path: r'C:\Games\Example',
          ),
        );

    expect(bridge.addedPaths, <String>[r'C:\Games\Example']);
    expect(bridge.compressedPaths, <String>[r'C:\Games\Example']);
    expect(bridge.decompressedPaths, isEmpty);
  });

  test(
    'decompress shell action hydrates and only runs for compressed target',
    () async {
      final bridge = _ShellActionBridge(
        hydrated: GameInfo(
          name: 'Example',
          path: r'C:\Games\Example',
          platform: Platform.application,
          sizeBytes: 100,
          compressedSize: 60,
          isCompressed: true,
        ),
      );
      final container = _container(bridge);
      addTearDown(container.dispose);

      await container
          .read(shellActionExecutorProvider)
          .execute(
            const ShellActionRequest(
              kind: ShellActionKind.decompress,
              path: r'C:\Games\Example',
            ),
          );

      expect(bridge.addedPaths, <String>[r'C:\Games\Example']);
      expect(bridge.decompressedPaths, <String>[r'C:\Games\Example']);
      expect(bridge.compressedPaths, isEmpty);
    },
  );

  test(
    'decompress shell action does not run for uncompressed target',
    () async {
      final bridge = _ShellActionBridge();
      final container = _container(bridge);
      addTearDown(container.dispose);

      await container
          .read(shellActionExecutorProvider)
          .execute(
            const ShellActionRequest(
              kind: ShellActionKind.decompress,
              path: r'C:\Games\Example',
            ),
          );

      expect(bridge.addedPaths, <String>[r'C:\Games\Example']);
      expect(bridge.decompressedPaths, isEmpty);
    },
  );

  test(
    'shortcut resolution failure blocks shell action before import',
    () async {
      final bridge = _ShellActionBridge();
      final container = _container(
        bridge,
        resolver: _FailingShortcutResolver(),
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(shellActionExecutorProvider)
            .execute(
              const ShellActionRequest(
                kind: ShellActionKind.compress,
                path: r'C:\Users\subai\Desktop\Example.lnk',
              ),
            ),
        throwsStateError,
      );
      expect(bridge.addedPaths, isEmpty);
      expect(bridge.compressedPaths, isEmpty);
    },
  );

  test(
    'active manual job rejects shell action without importing target',
    () async {
      final bridge = _ShellActionBridge(keepCompressionOpen: true);
      final container = _container(bridge);
      addTearDown(container.dispose);

      await container
          .read(compressionProvider.notifier)
          .startCompression(gamePath: r'C:\Games\Active', gameName: 'Active');
      expect(container.read(compressionProvider).hasActiveJob, isTrue);

      await container
          .read(shellActionExecutorProvider)
          .execute(
            const ShellActionRequest(
              kind: ShellActionKind.compress,
              path: r'C:\Games\Example',
            ),
          );

      expect(bridge.addedPaths, isEmpty);
      expect(bridge.compressedPaths, <String>[r'C:\Games\Active']);
    },
  );
}

ProviderContainer _container(
  _ShellActionBridge bridge, {
  ShellShortcutResolver? resolver,
}) {
  return ProviderContainer(
    overrides: [
      rustBridgeServiceProvider.overrideWithValue(bridge),
      if (resolver != null)
        shellShortcutResolverProvider.overrideWithValue(resolver),
    ],
  );
}

class _ShellActionBridge extends NoOpRustBridgeService {
  _ShellActionBridge({this.hydrated, this.keepCompressionOpen = false});

  final GameInfo? hydrated;
  final bool keepCompressionOpen;
  final List<String> addedPaths = <String>[];
  final List<String> compressedPaths = <String>[];
  final List<String> decompressedPaths = <String>[];
  final List<StreamController<CompressionProgress>> _controllers =
      <StreamController<CompressionProgress>>[];

  @override
  Future<GameInfo> addApplicationFolder(String path, {String? name}) async {
    addedPaths.add(path);
    return GameInfo(
      name: name ?? 'Example',
      path: path,
      platform: Platform.application,
      sizeBytes: 100,
    );
  }

  @override
  Future<GameInfo?> hydrateGame({
    required String gamePath,
    required String gameName,
    required Platform platform,
  }) async {
    return hydrated;
  }

  @override
  Stream<CompressionProgress> compressGame({
    required String gamePath,
    required String gameName,
    CompressionAlgorithm algorithm = CompressionAlgorithm.xpress8k,
    bool allowDirectStorageOverride = false,
    int? ioParallelismOverride,
  }) {
    compressedPaths.add(gamePath);
    return _stream();
  }

  @override
  Stream<CompressionProgress> decompressGame(
    String gamePath, {
    required String gameName,
    int? ioParallelismOverride,
  }) {
    decompressedPaths.add(gamePath);
    return _stream();
  }

  Stream<CompressionProgress> _stream() {
    if (!keepCompressionOpen) {
      return const Stream<CompressionProgress>.empty();
    }
    final controller = StreamController<CompressionProgress>();
    _controllers.add(controller);
    return controller.stream;
  }
}

class _FailingShortcutResolver implements ShellShortcutResolver {
  @override
  Future<String> resolveShortcutTarget(String shortcutPath) async {
    throw StateError('cannot resolve shortcut');
  }
}
