import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../models/game_info.dart';
import '../../../../providers/compression/compression_provider.dart';
import '../../../../providers/games/filtered_games_provider.dart';
import '../../../../providers/games/game_list_provider.dart';
import '../../../../providers/games/single_game_provider.dart';
import 'game_card.dart';

class HomeGameGrid extends ConsumerWidget {
  const HomeGameGrid({super.key});

  static const double _cardAspectRatio = 0.58;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(gameListProvider);

    return asyncState.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
      error: (error, _) => _ErrorView(
        message: error.toString(),
        onRetry: () => ref.read(gameListProvider.notifier).refresh(),
      ),
      data: (gameListState) {
        final loadError = gameListState.error;
        if (loadError != null && gameListState.games.isEmpty) {
          return _ErrorView(
            message: loadError,
            onRetry: () => ref.read(gameListProvider.notifier).refresh(),
          );
        }

        final games = ref.watch(filteredGamesProvider);
        if (games.isEmpty) {
          return const _EmptyView();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = _calculateColumns(constraints.maxWidth);
            return GridView.builder(
              padding: const EdgeInsets.all(AppConstants.gridSpacing),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: AppConstants.gridSpacing,
                mainAxisSpacing: AppConstants.gridSpacing,
                childAspectRatio: _cardAspectRatio,
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
    final columns =
        (availableWidth /
                (AppConstants.cardMinWidth + AppConstants.gridSpacing))
            .floor();
    return columns.clamp(2, 6);
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

  @override
  void didUpdateWidget(covariant _GameCardAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gamePath == widget.gamePath) {
      return;
    }

    _lastHydrationRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
    _hydrationRequestScheduled = false;
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(singleGameProvider(widget.gamePath));
    if (game == null) {
      return const SizedBox.shrink();
    }

    _scheduleHydrationRequest();

    return GameCard(
      gameName: game.name,
      totalSizeBytes: game.sizeBytes,
      compressedSizeBytes: game.compressedSize,
      isCompressed: game.isCompressed,
      isDirectStorage: game.isDirectStorage,
      onTap: () => _onGameTap(game),
    );
  }

  void _scheduleHydrationRequest() {
    if (_hydrationRequestScheduled) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastHydrationRequestAt) < _hydrationRequestInterval) {
      return;
    }

    _hydrationRequestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrationRequestScheduled = false;
      if (!mounted) {
        return;
      }

      _lastHydrationRequestAt = DateTime.now();
      ref.read(gameListProvider.notifier).requestHydration(widget.gamePath);
    });
  }

  void _onGameTap(GameInfo game) {
    if (game.isDirectStorage) return;
    if (game.isCompressed) {
      ref
          .read(compressionProvider.notifier)
          .startDecompression(gamePath: game.path, gameName: game.name);
    } else {
      ref
          .read(compressionProvider.notifier)
          .startCompression(gamePath: game.path, gameName: game.name);
    }
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.gamepad2,
            size: 48,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          const Text('No games found', style: AppTypography.headingSmall),
          const SizedBox(height: 8),
          Text(
            'Games from Steam, Epic, GOG, and other launchers\nwill appear here automatically.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.alertCircle, size: 48, color: AppColors.error),
          const SizedBox(height: 16),
          const Text('Failed to load games', style: AppTypography.headingSmall),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
