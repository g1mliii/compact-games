import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/cover_art_service.dart';
import '../games/single_game_provider.dart';
import '../settings/settings_provider.dart';

final CoverArtService _coverArtServiceSingleton = const CoverArtService();

final coverArtServiceProvider = Provider<CoverArtService>((ref) {
  return _coverArtServiceSingleton;
});

final coverArtProvider = FutureProvider.autoDispose
    .family<CoverArtResult, String>((ref, gamePath) async {
      // Keep provider alive once resolved to avoid dispose/recreate churn
      // during grid scrolling.  CoverArtResult is lightweight (a file path
      // or placeholder enum), so the memory cost is negligible.
      ref.keepAlive();

      // Only rebuild when fields that affect cover resolution change, not
      // when compression status or sizes change.
      final coverKey = ref.watch(
        singleGameProvider(gamePath).select(
          (g) => g == null
              ? null
              : (name: g.name, path: g.path, platform: g.platform),
        ),
      );
      if (coverKey == null) {
        return const CoverArtResult.none();
      }
      final apiKey = ref.watch(
        settingsProvider.select(
          (value) => value.valueOrNull?.settings.steamGridDbApiKey,
        ),
      );

      // Read the full game info for the service call (non-watching read).
      final game = ref.read(singleGameProvider(gamePath));
      if (game == null) {
        return const CoverArtResult.none();
      }
      final service = ref.read(coverArtServiceProvider);
      return service.resolveCover(game, steamGridDbApiKey: apiKey);
    });
