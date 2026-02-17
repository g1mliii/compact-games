import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/cover_art_service.dart';
import '../games/single_game_provider.dart';
import '../settings/settings_provider.dart';

final coverArtServiceProvider = Provider<CoverArtService>((ref) {
  return const CoverArtService();
});

final coverArtProvider = FutureProvider.autoDispose
    .family<CoverArtResult, String>((ref, gamePath) async {
      final game = ref.watch(singleGameProvider(gamePath));
      if (game == null) {
        return const CoverArtResult.none();
      }
      final apiKey = ref.watch(
        settingsProvider.select(
          (value) => value.valueOrNull?.settings.steamGridDbApiKey,
        ),
      );

      final service = ref.read(coverArtServiceProvider);
      return service.resolveCover(game, steamGridDbApiKey: apiKey);
    });
