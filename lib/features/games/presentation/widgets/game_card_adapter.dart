import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/utils/cover_art_utils.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../models/compression_algorithm.dart';
import '../../../../models/compression_estimate.dart';
import '../../../../models/game_info.dart';
import '../../../../providers/compression/compression_provider.dart';
import '../../../../providers/cover_art/cover_art_provider.dart';
import '../../../../providers/games/game_list_provider.dart';
import '../../../../providers/games/single_game_provider.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../../../../providers/system/platform_shell_provider.dart';

import 'game_card.dart';
import 'game_card_adapter_intents.dart';

class GameCardAdapter extends ConsumerStatefulWidget {
  const GameCardAdapter({super.key, required this.gamePath});

  final String gamePath;

  @override
  ConsumerState<GameCardAdapter> createState() => _GameCardAdapterState();
}

class _GameCardAdapterState extends ConsumerState<GameCardAdapter> {
  bool _hydrationRequested = false;
  bool _hydrationRequestScheduled = false;
  bool _estimateFetchScheduled = false;
  bool _estimateFetchInFlight = false;
  bool _compressionConfirmOpen = false;
  DateTime _nextEstimateAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);
  CompressionEstimate? _cachedEstimate;
  CompressionAlgorithm? _cachedEstimateAlgorithm;

  @override
  void didUpdateWidget(covariant GameCardAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gamePath != widget.gamePath) {
      _hydrationRequested = false;
      _hydrationRequestScheduled = false;
      _estimateFetchScheduled = false;
      _estimateFetchInFlight = false;
      _nextEstimateAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);
      _cachedEstimate = null;
      _cachedEstimateAlgorithm = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(singleGameProvider(widget.gamePath));
    if (game == null) return const SizedBox.shrink();
    final coverResult = ref
        .watch(coverArtProvider(widget.gamePath))
        .valueOrNull;
    final isExcluded = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.excludedPaths.contains(
              widget.gamePath,
            ) ??
            false,
      ),
    );

    _scheduleHydrationRequest();
    if (_isEstimatePrefetchAllowed(context)) {
      _scheduleEstimateFetch(game);
    }

    return FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
            CompressIntent(),
        SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true):
            ExcludeIntent(),
        SingleActivator(LogicalKeyboardKey.keyO, control: true, shift: true):
            OpenFolderIntent(),
        SingleActivator(LogicalKeyboardKey.keyD, control: true, shift: true):
            OpenDetailsIntent(),
        SingleActivator(LogicalKeyboardKey.f10, shift: true):
            ContextMenuIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            unawaited(_onGameTap(game));
            return null;
          },
        ),
        CompressIntent: CallbackAction<CompressIntent>(
          onInvoke: (_) {
            unawaited(_onGameTap(game));
            return null;
          },
        ),
        ExcludeIntent: CallbackAction<ExcludeIntent>(
          onInvoke: (_) {
            _toggleExclusion(game);
            return null;
          },
        ),
        OpenFolderIntent: CallbackAction<OpenFolderIntent>(
          onInvoke: (_) {
            unawaited(_openFolder(game.path));
            return null;
          },
        ),
        OpenDetailsIntent: CallbackAction<OpenDetailsIntent>(
          onInvoke: (_) {
            _openDetails(game.path);
            return null;
          },
        ),
        ContextMenuIntent: CallbackAction<ContextMenuIntent>(
          onInvoke: (_) {
            unawaited(_showContextMenu(game: game, isExcluded: isExcluded));
            return null;
          },
        ),
      },
      child: GameCard(
        gameName: game.name,
        platform: game.platform,
        totalSizeBytes: game.sizeBytes,
        compressedSizeBytes: game.compressedSize,
        isCompressed: game.isCompressed,
        isDirectStorage: game.isDirectStorage,
        estimatedSavedBytes: _estimatedSavedBytesFor(game),
        assumeBoundedHeight: true,
        coverImageProvider: imageProviderFromCover(coverResult),
        heroTag: null,
        onTap: () => unawaited(_onGameTap(game)),
        onSecondaryTapDown: (details) => unawaited(
          _showContextMenu(
            game: game,
            isExcluded: isExcluded,
            tapDown: details,
          ),
        ),
      ),
    );
  }

  int? _estimatedSavedBytesFor(GameInfo game) {
    if (game.isCompressed || game.isDirectStorage) return null;
    return _cachedEstimate?.estimatedSavedBytes;
  }

  void _scheduleEstimateFetch(GameInfo game) {
    if (game.isCompressed || game.isDirectStorage) return;
    if (_cachedEstimate != null) return;
    if (_estimateFetchScheduled) return;
    if (_estimateFetchInFlight) return;
    if (DateTime.now().isBefore(_nextEstimateAttemptAt)) return;

    final algorithm =
        ref.read(settingsProvider).valueOrNull?.settings.algorithm ??
        CompressionAlgorithm.xpress8k;
    if (_cachedEstimateAlgorithm == algorithm) return;
    _estimateFetchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _estimateFetchScheduled = false;
      if (!mounted) return;
      unawaited(
        _getCompressionEstimate(gamePath: game.path, algorithm: algorithm),
      );
    });
  }

  bool _isEstimatePrefetchAllowed(BuildContext context) {
    return !Scrollable.recommendDeferredLoadingForContext(context);
  }

  void _scheduleHydrationRequest() {
    if (_hydrationRequested) return;
    if (_hydrationRequestScheduled) return;

    _hydrationRequestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrationRequestScheduled = false;
      if (!mounted) return;
      _hydrationRequested = true;
      ref.read(gameListProvider.notifier).requestHydration(widget.gamePath);
    });
  }

  Future<void> _onGameTap(GameInfo game) async {
    if (game.isCompressed) {
      await ref
          .read(compressionProvider.notifier)
          .startDecompression(gamePath: game.path, gameName: game.name);
      return;
    }
    if (game.isDirectStorage) return;

    final shouldCompress = await _confirmCompression(gameName: game.name);
    if (!mounted || !shouldCompress) return;

    await ref
        .read(compressionProvider.notifier)
        .startCompression(gamePath: game.path, gameName: game.name);
  }

  void _openDetails(String gamePath) {
    Navigator.of(context).pushNamed(AppRoutes.gameDetails(gamePath));
  }

  Future<void> _openFolder(String gamePath) async {
    await ref.read(platformShellServiceProvider).openFolder(gamePath);
  }

  void _toggleExclusion(GameInfo game) {
    ref.read(settingsProvider.notifier).toggleGameExclusion(game.path);
  }

  Future<void> _showContextMenu({
    required GameInfo game,
    required bool isExcluded,
    TapDownDetails? tapDown,
  }) async {
    final action = await showMenu<GameContextAction>(
      context: context,
      position: _menuPosition(tapDown),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      items: [
        PopupMenuItem(
          value: GameContextAction.viewDetails,
          child: _buildMenuLabel('View Details', LucideIcons.info),
        ),
        PopupMenuItem(
          value: GameContextAction.compress,
          enabled: !game.isCompressed && !game.isDirectStorage,
          child: _buildMenuLabel('Compress Now', LucideIcons.archive),
        ),
        PopupMenuItem(
          value: GameContextAction.decompress,
          enabled: game.isCompressed,
          child: _buildMenuLabel('Decompress', LucideIcons.archiveRestore),
        ),
        PopupMenuItem(
          value: GameContextAction.exclude,
          child: _buildMenuLabel(
            isExcluded ? 'Include In Auto-Compression' : 'Exclude',
            isExcluded ? LucideIcons.checkCircle2 : LucideIcons.ban,
          ),
        ),
        PopupMenuItem(
          value: GameContextAction.openFolder,
          child: _buildMenuLabel('Open Folder', LucideIcons.folderOpen),
        ),
      ],
    );

    if (!mounted || action == null) return;
    switch (action) {
      case GameContextAction.viewDetails:
        _openDetails(game.path);
        break;
      case GameContextAction.compress:
        await ref
            .read(compressionProvider.notifier)
            .startCompression(gamePath: game.path, gameName: game.name);
        break;
      case GameContextAction.decompress:
        await ref
            .read(compressionProvider.notifier)
            .startDecompression(gamePath: game.path, gameName: game.name);
        break;
      case GameContextAction.exclude:
        _toggleExclusion(game);
        break;
      case GameContextAction.openFolder:
        await _openFolder(game.path);
        break;
    }
  }

  RelativeRect _menuPosition(TapDownDetails? tapDown) {
    if (tapDown != null) {
      final position = tapDown.globalPosition;
      return RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      );
    }

    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox) {
      final center = renderObject.localToGlobal(
        renderObject.size.center(Offset.zero),
      );
      return RelativeRect.fromLTRB(center.dx, center.dy, center.dx, center.dy);
    }

    return const RelativeRect.fromLTRB(0, 0, 0, 0);
  }

  Widget _buildMenuLabel(String text, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 16), const SizedBox(width: 8), Text(text)],
    );
  }

  Future<bool> _confirmCompression({required String gameName}) async {
    if (_compressionConfirmOpen) return false;

    _compressionConfirmOpen = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Compression'),
          content: Text(
            'Compress "$gameName"? This can affect disk usage and performance while running.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Compress'),
            ),
          ],
        ),
      );
      return confirmed ?? false;
    } finally {
      _compressionConfirmOpen = false;
    }
  }

  Future<CompressionEstimate?> _getCompressionEstimate({
    required String gamePath,
    required CompressionAlgorithm algorithm,
  }) async {
    if (_cachedEstimate != null && _cachedEstimateAlgorithm == algorithm) {
      return _cachedEstimate;
    }
    if (_estimateFetchInFlight) {
      return null;
    }

    _estimateFetchInFlight = true;
    try {
      final estimate = await ref
          .read(rustBridgeServiceProvider)
          .estimateCompressionSavings(gamePath: gamePath, algorithm: algorithm);
      ref.read(coverArtServiceProvider).primeEstimateHints(gamePath, estimate);
      ref.invalidate(coverArtProvider(gamePath));
      if (!mounted) return estimate;
      setState(() {
        _cachedEstimate = estimate;
        _cachedEstimateAlgorithm = algorithm;
      });
      return estimate;
    } catch (_) {
      _nextEstimateAttemptAt = DateTime.now().add(const Duration(seconds: 2));
      return null;
    } finally {
      _estimateFetchInFlight = false;
    }
  }
}
