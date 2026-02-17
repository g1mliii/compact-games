import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../providers/games/filtered_games_provider.dart';
import '../../../../providers/games/game_list_provider.dart';
import 'game_card_adapter.dart';
import 'game_grid_placeholders.dart';

class HomeGameGrid extends ConsumerWidget {
  const HomeGameGrid({super.key});

  static const EdgeInsets _gridPadding = EdgeInsets.fromLTRB(24, 20, 24, 24);
  static const double _defaultCardAspectRatio = 0.82;

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

        return GridView.builder(
          padding: _gridPadding,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: AppConstants.cardMaxWidth,
            crossAxisSpacing: AppConstants.gridSpacing,
            mainAxisSpacing: AppConstants.gridSpacing,
            childAspectRatio: _defaultCardAspectRatio,
          ),
          addRepaintBoundaries: false,
          itemCount: games.length,
          itemBuilder: (context, index) => GameCardAdapter(
            key: ValueKey(games[index].path),
            gamePath: games[index].path,
          ),
        );
      },
    );
  }
}
