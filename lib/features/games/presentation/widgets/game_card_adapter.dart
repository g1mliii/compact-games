import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/utils/cover_art_utils.dart';
import '../../../../core/utils/date_time_format.dart';
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
import 'game_actions.dart';
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

  // Mutable references for the stable action callbacks below.
  GameInfo? _currentGame;
  bool _currentIsExcluded = false;
  bool _currentDirectStorageOverride = false;

  // Stable action map — created once per state, callbacks read mutable
  // _currentGame/_currentIsExcluded so they always act on the latest values.
  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
        CompressIntent(),
    SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true):
        ExcludeIntent(),
    SingleActivator(LogicalKeyboardKey.keyO, control: true, shift: true):
        OpenFolderIntent(),
    SingleActivator(LogicalKeyboardKey.keyD, control: true, shift: true):
        OpenDetailsIntent(),
    SingleActivator(LogicalKeyboardKey.f10, shift: true): ContextMenuIntent(),
  };

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        final game = _currentGame;
        if (game != null) unawaited(_onGameTap(game));
        return null;
      },
    ),
    CompressIntent: CallbackAction<CompressIntent>(
      onInvoke: (_) {
        final game = _currentGame;
        if (game != null) unawaited(_onGameTap(game));
        return null;
      },
    ),
    ExcludeIntent: CallbackAction<ExcludeIntent>(
      onInvoke: (_) {
        final game = _currentGame;
        if (game != null) _toggleExclusion(game);
        return null;
      },
    ),
    OpenFolderIntent: CallbackAction<OpenFolderIntent>(
      onInvoke: (_) {
        final game = _currentGame;
        if (game != null) unawaited(_openFolder(game.path));
        return null;
      },
    ),
    OpenDetailsIntent: CallbackAction<OpenDetailsIntent>(
      onInvoke: (_) {
        final game = _currentGame;
        if (game != null) _openDetails(game.path);
        return null;
      },
    ),
    ContextMenuIntent: CallbackAction<ContextMenuIntent>(
      onInvoke: (_) {
        final game = _currentGame;
        if (game != null) {
          unawaited(
            _showContextMenu(
              game: game,
              isExcluded: _currentIsExcluded,
              allowDirectStorageOverride: _currentDirectStorageOverride,
            ),
          );
        }
        return null;
      },
    ),
  };

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
    final coverResult = ref.watch(
      coverArtProvider(widget.gamePath).select((v) => v.valueOrNull),
    );
    final isExcluded = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.excludedPaths.contains(
              widget.gamePath,
            ) ??
            false,
      ),
    );
    final allowDirectStorageOverride = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.directStorageOverrideEnabled ?? false,
      ),
    );

    // Update mutable references for the stable action callbacks.
    _currentGame = game;
    _currentIsExcluded = isExcluded;
    _currentDirectStorageOverride = allowDirectStorageOverride;

    _scheduleHydrationRequest();
    if (_isEstimatePrefetchAllowed(context)) {
      _scheduleEstimateFetch(game, allowDirectStorageOverride);
    }

    return FocusableActionDetector(
      shortcuts: _shortcuts,
      actions: _actions,
      mouseCursor: SystemMouseCursors.click,
      child: GameCard(
        gameName: game.name,
        platform: game.platform,
        totalSizeBytes: game.sizeBytes,
        compressedSizeBytes: game.compressedSize,
        isCompressed: game.isCompressed,
        isDirectStorage: game.isDirectStorage,
        isUnsupported: game.isUnsupported,
        estimatedSavedBytes: _estimatedSavedBytesFor(
          game,
          allowDirectStorageOverride,
        ),
        lastCompressedText: _lastCompressedText(game),
        assumeBoundedHeight: true,
        coverImageProvider: imageProviderFromCover(coverResult),
        heroTag: null,
        onTap: () => unawaited(
          _showContextMenu(
            game: game,
            isExcluded: isExcluded,
            allowDirectStorageOverride: allowDirectStorageOverride,
          ),
        ),
        onSecondaryTapDown: (details) => unawaited(
          _showContextMenu(
            game: game,
            isExcluded: isExcluded,
            allowDirectStorageOverride: allowDirectStorageOverride,
            tapDown: details,
          ),
        ),
      ),
    );
  }

  /// Whether DirectStorage protection blocks compression.
  static bool _isDirectStorageBlocked(GameInfo game, bool allowOverride) =>
      game.isDirectStorage && !allowOverride;

  int? _estimatedSavedBytesFor(GameInfo game, bool allowDirectStorageOverride) {
    if (game.isCompressed) return null;
    if (_isDirectStorageBlocked(game, allowDirectStorageOverride)) return null;
    return _cachedEstimate?.estimatedSavedBytes;
  }

  String? _lastCompressedText(GameInfo game) {
    final lastCompressed = game.lastCompressed;
    if (lastCompressed == null) {
      return null;
    }
    return formatLocalMonthDayTime(lastCompressed);
  }

  void _scheduleEstimateFetch(GameInfo game, bool allowDirectStorageOverride) {
    if (game.isCompressed) return;
    if (_isDirectStorageBlocked(game, allowDirectStorageOverride)) return;
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
    final allowDirectStorageOverride =
        ref
            .read(settingsProvider)
            .valueOrNull
            ?.settings
            .directStorageOverrideEnabled ??
        false;

    if (game.isCompressed) {
      await ref
          .read(compressionProvider.notifier)
          .startDecompression(gamePath: game.path, gameName: game.name);
      return;
    }
    if (_isDirectStorageBlocked(game, allowDirectStorageOverride)) return;

    final shouldCompress = await _confirmCompression(gameName: game.name);
    if (!mounted || !shouldCompress) return;

    await ref
        .read(compressionProvider.notifier)
        .startCompression(
          gamePath: game.path,
          gameName: game.name,
          allowDirectStorageOverride: allowDirectStorageOverride,
        );
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

  void _setUnsupportedStatus(GameInfo game, {required bool isUnsupported}) {
    toggleGameUnsupportedStatus(
      ref, context, game, markUnsupported: isUnsupported,
    );
  }

  Future<void> _showContextMenu({
    required GameInfo game,
    required bool isExcluded,
    required bool allowDirectStorageOverride,
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
          enabled:
              !game.isCompressed &&
              !_isDirectStorageBlocked(game, allowDirectStorageOverride),
          child: _buildMenuLabel('Compress Now', LucideIcons.archive),
        ),
        PopupMenuItem(
          value: GameContextAction.decompress,
          enabled: game.isCompressed,
          child: _buildMenuLabel('Decompress', LucideIcons.archiveRestore),
        ),
        PopupMenuItem(
          value: game.isUnsupported
              ? GameContextAction.markSupported
              : GameContextAction.markUnsupported,
          child: _buildMenuLabel(
            game.isUnsupported ? 'Mark as Supported' : 'Mark as Unsupported',
            game.isUnsupported ? LucideIcons.checkCircle2 : LucideIcons.ban,
          ),
        ),
        PopupMenuItem(
          value: GameContextAction.exclude,
          child: _buildMenuLabel(
            isExcluded ? 'Include In Auto-Compression' : 'Exclude From Auto-Compression',
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
            .startCompression(
              gamePath: game.path,
              gameName: game.name,
              allowDirectStorageOverride: allowDirectStorageOverride,
            );
        break;
      case GameContextAction.decompress:
        await ref
            .read(compressionProvider.notifier)
            .startDecompression(gamePath: game.path, gameName: game.name);
        break;
      case GameContextAction.markUnsupported:
        _setUnsupportedStatus(game, isUnsupported: true);
        break;
      case GameContextAction.markSupported:
        _setUnsupportedStatus(game, isUnsupported: false);
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
    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
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
      if (!mounted) return estimate;
      ref.read(coverArtServiceProvider).primeEstimateHints(gamePath, estimate);
      ref.invalidate(coverArtProvider(gamePath));
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
