import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_info.dart';
import '../compression/compression_provider.dart';
import 'game_list_provider.dart';

/// Derived map for O(1) per-game lookup keyed by absolute game path.
final gamesByPathProvider = Provider<Map<String, GameInfo>>((ref) {
  final games = ref.watch(
    gameListProvider.select((state) => state.valueOrNull?.games),
  );
  if (games == null) {
    return const {};
  }
  return {for (final game in games) game.path: game};
});

/// Family provider for per-game access.
/// Used by GameCard to watch only its own game's data.
/// Avoids full grid rebuild when one game changes.
final singleGameProvider = Provider.family<GameInfo?, String>((ref, gamePath) {
  return ref.watch(
    gamesByPathProvider.select((gamesByPath) => gamesByPath[gamePath]),
  );
});

/// Whether a specific game is currently being compressed.
final isGameCompressingProvider = Provider.family<bool, String>((
  ref,
  gamePath,
) {
  return ref.watch(
    compressionProvider.select((s) {
      final job = s.activeJob;
      return job != null && job.gamePath == gamePath && job.isActive;
    }),
  );
});
