import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cover_art/cover_art_provider.dart';
import 'game_list_provider.dart';

/// Shared refresh-and-invalidate logic used by both the home header and
/// inventory screen.  Avoids duplicating the same provider reads and
/// cover-art cache invalidation in two places.
/// Returns whether the reload actually ran; false means a concurrent refresh
/// owned it, which callers reporting an outcome to the user must not treat as
/// a completed rescan.
Future<bool> refreshGamesAndInvalidateCovers(WidgetRef ref) async {
  final refreshed = await ref.read(gameListProvider.notifier).refresh();

  final games = ref.read(gameListProvider).value?.games ?? const [];
  if (games.isEmpty) return refreshed;

  final paths = games.map((game) => game.path).toList(growable: false);
  final coverArtService = ref.read(coverArtServiceProvider);
  final placeholders = coverArtService.placeholderRefreshCandidates(paths);
  if (placeholders.isEmpty) return refreshed;

  coverArtService.clearLookupCaches();
  coverArtService.invalidateCoverForGames(placeholders);
  for (final path in placeholders) {
    ref.invalidate(coverArtProvider(path));
  }
  return refreshed;
}
