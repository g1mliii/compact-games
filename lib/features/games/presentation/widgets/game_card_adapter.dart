import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/localization/app_localization.dart';
import '../../../../core/performance/ui_memory_lifecycle.dart';
import '../../../../core/theme/app_colors.dart';
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
import '../../../../services/cover_art_service.dart';
import 'game_actions.dart';
import 'game_card.dart';
import 'game_card_adapter_intents.dart';

class GameCardAdapter extends ConsumerStatefulWidget {
  const GameCardAdapter({super.key, required this.gamePath});

  final String gamePath;

  @override
  ConsumerState<GameCardAdapter> createState() => _GameCardAdapterState();
}

class _GameCardAdapterState extends ConsumerState<GameCardAdapter>
    with AutomaticKeepAliveClientMixin {
  /// Keep the card alive when it has completed hydration work (cover art or
  /// estimate fetched), so scrolling back doesn't re-trigger async work.
  /// Gated by image cache budget to avoid unbounded memory growth.
  static const int _keepAliveCacheBudget = 150 * 1024 * 1024; // 150 MB

  @override
  bool get wantKeepAlive =>
      (_cachedCoverUri != null || _cachedEstimate != null) &&
      UiMemoryLifecycle.currentImageCacheBytes < _keepAliveCacheBudget;

  static const double _contextMenuMinWidth = 184;
  static const double _contextMenuMaxWidth = 208;
  static const ValueKey<String> _dangerDividerKey = ValueKey<String>(
    'gameCardDangerDivider',
  );
  static const ValueKey<String> _cardContentKey = ValueKey<String>(
    'gameCardAdapterContent',
  );
  final FocusNode _focusNode = FocusNode();
  bool _hydrationRequested = false;
  bool _hydrationRequestScheduled = false;
  bool _estimateFetchScheduled = false;
  bool _estimateFetchInFlight = false;
  bool _compressionConfirmOpen = false;
  DateTime _nextEstimateAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);
  CompressionEstimate? _cachedEstimate;
  CompressionAlgorithm? _cachedEstimateAlgorithm;
  String? _cachedCoverUri;
  int _cachedCoverRevision = 0;
  ImageProvider<Object>? _cachedCoverImageProvider;

  /// Read the current game fresh from the provider. Used by keyboard action
  /// callbacks so they never act on a stale cached reference.
  GameInfo? _readCurrentGame() =>
      ref.read(singleGameProvider(widget.gamePath));

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
        final game = _readCurrentGame();
        if (game != null) unawaited(_onGameTap(game));
        return null;
      },
    ),
    CompressIntent: CallbackAction<CompressIntent>(
      onInvoke: (_) {
        final game = _readCurrentGame();
        if (game != null) unawaited(_onGameTap(game));
        return null;
      },
    ),
    ExcludeIntent: CallbackAction<ExcludeIntent>(
      onInvoke: (_) {
        final game = _readCurrentGame();
        if (game != null) _toggleExclusion(game);
        return null;
      },
    ),
    OpenFolderIntent: CallbackAction<OpenFolderIntent>(
      onInvoke: (_) {
        final game = _readCurrentGame();
        if (game != null) unawaited(_openFolder(game.path));
        return null;
      },
    ),
    OpenDetailsIntent: CallbackAction<OpenDetailsIntent>(
      onInvoke: (_) {
        final game = _readCurrentGame();
        if (game != null) _openDetails(game.path);
        return null;
      },
    ),
    ContextMenuIntent: CallbackAction<ContextMenuIntent>(
      onInvoke: (_) {
        final game = _readCurrentGame();
        if (game != null) {
          unawaited(_showContextMenu(game: game));
        }
        return null;
      },
    ),
  };

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

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
      _cachedCoverUri = null;
      _cachedCoverRevision = 0;
      _cachedCoverImageProvider = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    // Select only the fields actually rendered on the card so this widget does
    // not rebuild when unrelated GameInfo fields (e.g. excluded, lastPlayed)
    // change. A null selector result means the game was removed from the list.
    final cardData = ref.watch(
      singleGameProvider(widget.gamePath).select((game) {
        if (game == null) return null;
        return (
          name: game.name,
          platform: game.platform,
          sizeBytes: game.sizeBytes,
          compressedSize: game.compressedSize,
          isCompressed: game.isCompressed,
          isDirectStorage: game.isDirectStorage,
          isUnsupported: game.isUnsupported,
          path: game.path,
          lastCompressedAt: game.lastCompressedAt,
          lastPlayed: game.lastPlayed,
        );
      }),
    );
    if (cardData == null) return const SizedBox.shrink();
    // Read imperatively for estimate prefetch and context menu closures.
    final game = ref.read(singleGameProvider(widget.gamePath));
    if (game == null) return const SizedBox.shrink();
    final coverSnapshot = ref.watch(
      coverArtProvider(widget.gamePath).select((value) {
        final result = value.valueOrNull;
        return (
          uri: result?.uri,
          revision: result?.revision ?? 0,
          source: result?.source ?? CoverArtSource.none,
        );
      }),
    );
    final allowDirectStorageOverride = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.directStorageOverrideEnabled ?? false,
      ),
    );

    _scheduleHydrationRequest();
    if (_isEstimatePrefetchAllowed(context)) {
      _scheduleEstimateFetch(game, allowDirectStorageOverride);
    }
    final coverImageProvider = _coverImageProviderFor(coverSnapshot);
    final coverArtType = coverArtTypeFromSource(coverSnapshot.source);
    return FocusableActionDetector(
      key: _cardContentKey,
      focusNode: _focusNode,
      shortcuts: _shortcuts,
      actions: _actions,
      mouseCursor: SystemMouseCursors.click,
      child: GameCard(
        // Use cardData fields for rendering — these are the selected values
        // that control rebuild frequency.
        gameName: cardData.name,
        platform: cardData.platform,
        totalSizeBytes: cardData.sizeBytes,
        compressedSizeBytes: cardData.compressedSize,
        isCompressed: cardData.isCompressed,
        isDirectStorage: cardData.isDirectStorage,
        isUnsupported: cardData.isUnsupported,
        estimatedSavedBytes: _estimatedSavedBytesFor(
          game,
          allowDirectStorageOverride,
        ),
        lastCompressedText: _lastCompressedText(game),
        assumeBoundedHeight: true,
        coverImageProvider: coverImageProvider,
        coverArtType: coverArtType,
        heroTag: null,
        focusNode: _focusNode,
        onTap: () => unawaited(_showContextMenu(game: game)),
        onSecondaryTapDown: (details) =>
            unawaited(_showContextMenu(game: game, tapDown: details)),
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
    return formatLocalMonthDayTime(
      lastCompressed,
      locale: Localizations.localeOf(context),
    );
  }

  ImageProvider<Object>? _coverImageProviderFor(
    ({String? uri, int revision, CoverArtSource source}) coverSnapshot,
  ) {
    final coverUri = coverSnapshot.uri;
    final coverRevision = coverSnapshot.revision;
    if (_cachedCoverUri == coverUri && _cachedCoverRevision == coverRevision) {
      return _cachedCoverImageProvider;
    }

    _cachedCoverUri = coverUri;
    _cachedCoverRevision = coverRevision;
    _cachedCoverImageProvider = imageProviderFromCover(
      coverUri == null
          ? null
          : CoverArtResult(
              uri: coverUri,
              source: CoverArtSource.none,
              revision: coverRevision,
            ),
    );
    return _cachedCoverImageProvider;
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

  bool _readIsExcluded(String gamePath) {
    return ref
            .read(settingsProvider)
            .valueOrNull
            ?.settings
            .excludedPaths
            .contains(gamePath) ??
        false;
  }

  bool _readDirectStorageOverride() {
    return ref
            .read(settingsProvider)
            .valueOrNull
            ?.settings
            .directStorageOverrideEnabled ??
        false;
  }

  void _setUnsupportedStatus(GameInfo game, {required bool isUnsupported}) {
    toggleGameUnsupportedStatus(
      ref,
      context,
      game,
      markUnsupported: isUnsupported,
    );
  }

  Future<void> _showContextMenu({
    required GameInfo game,
    TapDownDetails? tapDown,
  }) async {
    final l10n = context.l10n;
    final isExcluded = _readIsExcluded(game.path);
    final allowDirectStorageOverride = _readDirectStorageOverride();
    final action = await showMenu<GameContextAction>(
      context: context,
      position: _menuPosition(tapDown),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      constraints: const BoxConstraints(
        minWidth: _contextMenuMinWidth,
        maxWidth: _contextMenuMaxWidth,
      ),
      items: [
        PopupMenuItem(
          value: GameContextAction.viewDetails,
          child: _buildMenuLabel(l10n.gameMenuViewDetails, LucideIcons.info),
        ),
        PopupMenuItem(
          value: GameContextAction.compress,
          enabled:
              !game.isCompressed &&
              !_isDirectStorageBlocked(game, allowDirectStorageOverride),
          child: _buildMenuLabel(l10n.gameMenuCompressNow, LucideIcons.archive),
        ),
        PopupMenuItem(
          value: GameContextAction.decompress,
          enabled: game.isCompressed,
          child: _buildMenuLabel(
            l10n.gameMenuDecompress,
            LucideIcons.archiveRestore,
          ),
        ),
        PopupMenuItem(
          value: game.isUnsupported
              ? GameContextAction.markSupported
              : GameContextAction.markUnsupported,
          child: _buildMenuLabel(
            game.isUnsupported
                ? l10n.gameMenuMarkSupported
                : l10n.gameMenuMarkUnsupported,
            game.isUnsupported ? LucideIcons.checkCircle2 : LucideIcons.ban,
          ),
        ),
        PopupMenuItem(
          value: GameContextAction.exclude,
          child: _buildMenuLabel(
            isExcluded
                ? l10n.gameMenuIncludeInAutoCompression
                : l10n.gameMenuExcludeFromAutoCompression,
            isExcluded ? LucideIcons.checkCircle2 : LucideIcons.ban,
          ),
        ),
        PopupMenuItem(
          value: GameContextAction.openFolder,
          child: _buildMenuLabel(l10n.commonOpenFolder, LucideIcons.folderOpen),
        ),
        PopupMenuItem<GameContextAction>(
          enabled: false,
          height: 14,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Divider(
            key: _dangerDividerKey,
            height: 1,
            thickness: 1,
            color: AppColors.borderSubtle,
          ),
        ),
        PopupMenuItem(
          value: GameContextAction.removeFromLibrary,
          child: _buildMenuLabel(
            l10n.gameMenuRemoveFromLibrary,
            LucideIcons.trash2,
            color: Colors.redAccent,
          ),
        ),
      ],
    );

    if (!mounted) return;
    // Restore keyboard focus to this card after menu dismissal.
    if (_focusNode.canRequestFocus) _focusNode.requestFocus();
    if (action == null) return;
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
      case GameContextAction.removeFromLibrary:
        _removeFromLibrary(game);
        break;
    }
  }

  void _removeFromLibrary(GameInfo game) {
    ref.read(gameListProvider.notifier).removeGameByPath(game.path);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.gameRemovedFromLibrary(game.name)),
          duration: const Duration(seconds: 3),
        ),
      );
    unawaited(_persistLibraryRemoval(game));
  }

  Future<void> _persistLibraryRemoval(GameInfo game) async {
    try {
      await ref
          .read(rustBridgeServiceProvider)
          .removeGameFromDiscovery(path: game.path, platform: game.platform);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.l10n.gameRemovalPersistFailed(game.name)),
            duration: const Duration(seconds: 4),
          ),
        );
      await ref.read(gameListProvider.notifier).refresh();
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

  Widget _buildMenuLabel(String text, IconData icon, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.fade,
            style:
                (color != null ? TextStyle(color: color) : null)?.copyWith(
                  fontSize: 13,
                  height: 1.15,
                ) ??
                const TextStyle(fontSize: 13, height: 1.15),
          ),
        ),
      ],
    );
  }

  Future<bool> _confirmCompression({required String gameName}) async {
    if (_compressionConfirmOpen) return false;

    _compressionConfirmOpen = true;
    try {
      final l10n = context.l10n;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.gameConfirmCompressionTitle),
          content: Text(l10n.gameConfirmCompressionMessage(gameName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.gameConfirmCompressionAction),
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
