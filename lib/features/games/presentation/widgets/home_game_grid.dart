import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../providers/games/filtered_games_provider.dart';
import '../../../../providers/games/game_list_provider.dart';
import 'game_card_adapter.dart';
import 'game_grid_placeholders.dart';

class HomeGameGrid extends ConsumerStatefulWidget {
  const HomeGameGrid({super.key});

  @override
  ConsumerState<HomeGameGrid> createState() => _HomeGameGridState();
}

class _HomeGameGridState extends ConsumerState<HomeGameGrid> {
  static const EdgeInsets _gridPadding = EdgeInsets.fromLTRB(24, 20, 24, 24);
  static const double _contentTopInset = 12;
  static const double _viewportWidthBucket = 32;
  static const double _coverTargetAspectRatio = 342 / 482;
  static const double _metadataSectionHeight = 90;
  static const double _fallbackCardAspectRatio = 0.56;
  static const double _minCardAspectRatio = 0.5;
  static const double _maxCardAspectRatio = 0.65;

  List<Object?>? _cachedSignature;
  Widget? _cachedGridViewport;

  @override
  void dispose() {
    _cachedSignature = null;
    _cachedGridViewport = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use .select() so the grid only rebuilds when loading/error state
    // actually changes, not on every game-list data mutation.
    final isLoading = ref.watch(gameListProvider.select((s) => s.isLoading));
    // Domain-level error stored inside GameListState (provider catches exceptions).
    final loadError = ref.watch(
      gameListProvider.select((s) => s.valueOrNull?.error),
    );
    final gamePaths = ref.watch(filteredGamePathsProvider);

    if (isLoading && gamePaths.isEmpty) {
      _cachedSignature = null;
      _cachedGridViewport = null;
      return const Center(
        child: CircularProgressIndicator(color: AppColors.richGold),
      );
    }

    if (loadError != null && gamePaths.isEmpty) {
      _cachedSignature = null;
      _cachedGridViewport = null;
      return GameGridErrorView(
        message: loadError,
        onRetry: () => ref.read(gameListProvider.notifier).refresh(),
      );
    }

    if (gamePaths.isEmpty) {
      _cachedSignature = null;
      _cachedGridViewport = null;
      return const GameGridEmptyView();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bucketedViewportWidth = _bucketViewportWidth(
          constraints.maxWidth,
        );
        final gridWidth = (bucketedViewportWidth - _gridPadding.horizontal)
            .clamp(AppConstants.cardMinWidth, double.infinity)
            .toDouble();
        final cardAspectRatio = _cardAspectRatioForGridWidth(gridWidth);
        final nextSignature = <Object?>[
          gamePaths,
          bucketedViewportWidth,
          cardAspectRatio,
        ];

        if (_hasMatchingGridSignature(nextSignature)) {
          return _cachedGridViewport!;
        }

        final gridViewport = Padding(
          padding: const EdgeInsets.only(top: _contentTopInset),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: bucketedViewportWidth,
              child: GridView.builder(
                padding: _gridPadding,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: AppConstants.cardMaxWidth,
                  crossAxisSpacing: AppConstants.gridSpacing,
                  mainAxisSpacing: AppConstants.gridSpacing,
                  childAspectRatio: cardAspectRatio,
                ),
                addRepaintBoundaries: true,
                itemCount: gamePaths.length,
                itemBuilder: (context, index) => GameCardAdapter(
                  key: ValueKey(gamePaths[index]),
                  gamePath: gamePaths[index],
                ),
              ),
            ),
          ),
        );

        _cachedSignature = nextSignature;
        _cachedGridViewport = gridViewport;
        return gridViewport;
      },
    );
  }

  bool _hasMatchingGridSignature(List<Object?> nextSignature) {
    final currentSignature = _cachedSignature;
    return currentSignature != null &&
        _cachedGridViewport != null &&
        listEquals(currentSignature, nextSignature);
  }

  static double _bucketViewportWidth(double viewportWidth) {
    if (!viewportWidth.isFinite || viewportWidth <= 0) {
      return viewportWidth;
    }

    final gridWidth = viewportWidth - _gridPadding.horizontal;
    if (gridWidth <= AppConstants.cardMinWidth + _viewportWidthBucket) {
      return viewportWidth;
    }

    final bucketedGridWidth =
        (gridWidth / _viewportWidthBucket).floor() * _viewportWidthBucket;
    return (bucketedGridWidth + _gridPadding.horizontal)
        .clamp(0.0, viewportWidth)
        .toDouble();
  }

  static double _cardAspectRatioForGridWidth(double gridWidth) {
    if (!gridWidth.isFinite || gridWidth <= 0) {
      return _fallbackCardAspectRatio;
    }

    final spacing = AppConstants.gridSpacing;
    final denominator = AppConstants.cardMaxWidth + spacing;
    final crossAxisCount = denominator > 0
        ? (gridWidth / denominator).ceil().clamp(1, 12)
        : 1;
    final totalSpacing = spacing * (crossAxisCount - 1);
    final cardWidth = (gridWidth - totalSpacing) / crossAxisCount;
    final coverHeight = cardWidth / _coverTargetAspectRatio;
    final totalHeight = coverHeight + _metadataSectionHeight;
    final ratio = cardWidth / totalHeight;
    return ratio.clamp(_minCardAspectRatio, _maxCardAspectRatio).toDouble();
  }
}
