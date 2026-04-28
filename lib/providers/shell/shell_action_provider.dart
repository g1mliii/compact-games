import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../models/game_info.dart';
import '../../services/shell_launch_args.dart';
import '../../src/rust/api/shell.dart' as rust_shell;
import '../compression/compression_provider.dart';
import '../games/game_list_provider.dart';

final shellShortcutResolverProvider = Provider<ShellShortcutResolver>((ref) {
  return const RustShellShortcutResolver();
});

final shellActionExecutorProvider = Provider<ShellActionExecutor>((ref) {
  return ShellActionExecutor(ref);
});

abstract interface class ShellShortcutResolver {
  Future<String> resolveShortcutTarget(String shortcutPath);
}

class RustShellShortcutResolver implements ShellShortcutResolver {
  const RustShellShortcutResolver();

  @override
  Future<String> resolveShortcutTarget(String shortcutPath) {
    return rust_shell.resolveShortcutTarget(shortcutPath: shortcutPath);
  }
}

class ShellActionExecutor {
  ShellActionExecutor(this._ref);

  final Ref _ref;

  Future<void> execute(ShellActionRequest request) async {
    if (_rejectIfActive(request)) return;

    final targetPath = await _resolveTargetPath(request.path);
    await _ref.read(gameListProvider.future);
    if (_rejectIfActive(request)) return;

    final imported = await _ref
        .read(gameListProvider.notifier)
        .addApplicationFromPathOrExe(targetPath);
    final game = await _hydrate(imported.game);

    if (_rejectIfActive(request)) return;

    switch (request.kind) {
      case ShellActionKind.compress:
        await _ref
            .read(compressionProvider.notifier)
            .startCompression(gamePath: game.path, gameName: game.name);
        break;
      case ShellActionKind.decompress:
        if (!game.isCompressed) {
          debugPrint('[shell] ignored decompress; target is not compressed');
          return;
        }
        await _ref
            .read(compressionProvider.notifier)
            .startDecompression(gamePath: game.path, gameName: game.name);
        break;
    }
  }

  Future<String> _resolveTargetPath(String rawPath) async {
    final path = rawPath.trim();
    if (path.isEmpty) {
      throw ArgumentError('Shell action path cannot be empty.');
    }
    if (p.extension(path).toLowerCase() != '.lnk') {
      return path;
    }
    final resolved = await _ref
        .read(shellShortcutResolverProvider)
        .resolveShortcutTarget(path);
    final normalized = resolved.trim();
    if (normalized.isEmpty) {
      throw StateError('Shortcut target could not be resolved.');
    }
    return normalized;
  }

  Future<GameInfo> _hydrate(GameInfo game) async {
    final hydrated = await _ref
        .read(rustBridgeServiceProvider)
        .hydrateGame(
          gamePath: game.path,
          gameName: game.name,
          platform: game.platform,
        );
    if (hydrated == null) {
      return game;
    }
    _ref.read(gameListProvider.notifier).updateGame(hydrated);
    return hydrated;
  }

  bool _hasActiveManualJob() {
    return _ref.read(compressionProvider).hasActiveJob;
  }

  // The shell-action chain in `_EffectProviderHostState` already serializes
  // requests, so a second action can't start while the first is still
  // executing on this side. We still re-check `hasActiveJob` between
  // every async hop because compression can be started elsewhere (the
  // game grid, the details screen, automation) and shell actions must
  // never preempt or interleave with a manual job already in flight.
  bool _rejectIfActive(ShellActionRequest request) {
    if (!_hasActiveManualJob()) return false;
    debugPrint('[shell] ignored ${request.kind.wireName}; job already active');
    return true;
  }
}
