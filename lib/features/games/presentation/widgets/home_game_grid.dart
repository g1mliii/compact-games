import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../models/compression_algorithm.dart';
import '../../../../models/compression_estimate.dart';
import '../../../../models/game_info.dart';
import '../../../../providers/compression/compression_provider.dart';
import '../../../../providers/games/filtered_games_provider.dart';
import '../../../../providers/games/game_list_provider.dart';
import '../../../../providers/games/single_game_provider.dart';
import '../../../../providers/settings/settings_provider.dart';
import 'game_card.dart';
import 'game_grid_placeholders.dart';

class HomeGameGrid extends ConsumerWidget {
  const HomeGameGrid({super.key});

  static const EdgeInsets _gridPadding = EdgeInsets.fromLTRB(24, 20, 24, 24);
  static const double _defaultCardAspectRatio = 0.54;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch gameListProvider for loading/error states
    final asyncState = ref.watch(gameListProvider);
    // Only watch filteredGamesProvider once (it already depends on gameListProvider)
    final games = ref.watch(filteredGamesProvider);

    return asyncState.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.richGold),
      ),
      error: (error, _) => GameGridErrorView(
        message: error.toString(),
        onRetry: () => ref.read(gameListProvider.notifier).refresh(),
      ),
      data: (gameListState) {
        final loadError = gameListState.error;
        if (loadError != null && gameListState.games.isEmpty) {
          return GameGridErrorView(
            message: loadError,
            onRetry: () => ref.read(gameListProvider.notifier).refresh(),
          );
        }

        if (games.isEmpty) {
          return const GameGridEmptyView();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = _calculateColumns(constraints.maxWidth);
            final childAspectRatio = _cardAspectRatioFor(crossAxisCount);
            return GridView.builder(
              padding: _gridPadding,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: AppConstants.gridSpacing,
                mainAxisSpacing: AppConstants.gridSpacing,
                childAspectRatio: childAspectRatio,
              ),
              itemCount: games.length,
              itemBuilder: (context, index) => _GameCardAdapter(
                key: ValueKey(games[index].path),
                gamePath: games[index].path,
              ),
            );
          },
        );
      },
    );
  }

  int _calculateColumns(double availableWidth) {
    final contentWidth = availableWidth - _gridPadding.horizontal;
    final normalizedWidth = contentWidth > AppConstants.cardMinWidth
        ? contentWidth
        : AppConstants.cardMinWidth;
    final columns =
        (normalizedWidth /
                (AppConstants.cardMinWidth + AppConstants.gridSpacing))
            .floor();
    return columns.clamp(1, 5);
  }

  double _cardAspectRatioFor(int crossAxisCount) {
    if (crossAxisCount <= 2) return 0.53;
    if (crossAxisCount == 3) return 0.54;
    return _defaultCardAspectRatio;
  }
}

class _GameCardAdapter extends ConsumerStatefulWidget {
  const _GameCardAdapter({super.key, required this.gamePath});

  final String gamePath;

  @override
  ConsumerState<_GameCardAdapter> createState() => _GameCardAdapterState();
}

class _GameCardAdapterState extends ConsumerState<_GameCardAdapter> {
  static const Duration _hydrationRequestInterval = Duration(seconds: 1);

  DateTime _lastHydrationRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _hydrationRequestScheduled = false;
  bool _estimateFetchScheduled = false;
  bool _estimateFetchInFlight = false;
  bool _compressionConfirmOpen = false;
  CompressionEstimate? _cachedEstimate;
  CompressionAlgorithm? _cachedEstimateAlgorithm;

  @override
  void didUpdateWidget(covariant _GameCardAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gamePath != widget.gamePath) {
      _lastHydrationRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
      _hydrationRequestScheduled = false;
      _estimateFetchScheduled = false;
      _estimateFetchInFlight = false;
      _cachedEstimate = null;
      _cachedEstimateAlgorithm = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(singleGameProvider(widget.gamePath));
    if (game == null) return const SizedBox.shrink();

    _scheduleHydrationRequest();
    _scheduleEstimateFetch(game);

    return GameCard(
      gameName: game.name,
      totalSizeBytes: game.sizeBytes,
      compressedSizeBytes: game.compressedSize,
      isCompressed: game.isCompressed,
      isDirectStorage: game.isDirectStorage,
      estimatedSavedBytes: _estimatedSavedBytesFor(game),
      onTap: () => unawaited(_onGameTap(game)),
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

    final algorithm =
        ref.read(settingsProvider).valueOrNull?.settings.algorithm ??
        CompressionAlgorithm.xpress8k;

    if (_cachedEstimateAlgorithm == algorithm) return;

    _estimateFetchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _estimateFetchScheduled = false;
      if (!mounted) return;
      // Fire-and-forget; rebuild will pick up the result via setState.
      unawaited(
        _getCompressionEstimate(gamePath: game.path, algorithm: algorithm),
      );
    });
  }

  void _scheduleHydrationRequest() {
    if (_hydrationRequestScheduled) return;

    final now = DateTime.now();
    if (now.difference(_lastHydrationRequestAt) < _hydrationRequestInterval) {
      return;
    }

    _hydrationRequestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrationRequestScheduled = false;
      if (!mounted) return;
      _lastHydrationRequestAt = DateTime.now();
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
      setState(() {
        _cachedEstimate = estimate;
        _cachedEstimateAlgorithm = algorithm;
      });
      return estimate;
    } catch (_) {
      return null;
    } finally {
      _estimateFetchInFlight = false;
    }
  }
}
