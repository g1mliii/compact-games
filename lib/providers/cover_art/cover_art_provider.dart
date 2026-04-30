import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/cover_art_proxy_config.dart';
import '../../services/cover_art_service.dart';
import '../games/game_list_provider.dart';
import '../games/single_game_provider.dart';
import '../settings/settings_provider.dart';

final CoverArtService _coverArtServiceSingleton = const CoverArtService();

final coverArtServiceProvider = Provider<CoverArtService>((ref) {
  return _coverArtServiceSingleton;
});

final coverArtProvider = FutureProvider.autoDispose
    .family<CoverArtResult, String>((ref, gamePath) async {
      // Keep provider alive for 30 seconds after it is no longer watched to
      // avoid dispose/recreate churn during grid scrolling, without causing
      // unbounded memory growth for large game libraries.
      if (kReleaseMode) {
        final link = ref.keepAlive();
        Timer? timer;
        ref.onDispose(() => timer?.cancel());
        ref.onCancel(() {
          timer = Timer(const Duration(seconds: 30), link.close);
        });
        ref.onResume(() {
          timer?.cancel();
          timer = null;
        });
      }

      // Only rebuild when fields that affect cover resolution change, not
      // when compression status or sizes change.
      final coverKey = ref.watch(
        singleGameProvider(gamePath).select(
          (g) => g == null
              ? null
              : (
                  name: g.name,
                  path: g.path,
                  platform: g.platform,
                  steamAppId: g.steamAppId,
                ),
        ),
      );
      if (coverKey == null) {
        return const CoverArtResult.none();
      }
      // Wait for settings without selectAsync; that Riverpod path can read
      // after ProviderContainer disposal in widget tests.
      final settingsState = await ref.watch(settingsProvider.future);
      final coverSettings = (
        apiKey: settingsState.settings.steamGridDbApiKey,
        mode: settingsState.settings.coverArtProviderMode,
      );

      final game = ref.read(singleGameProvider(gamePath));
      if (game == null) {
        return const CoverArtResult.none();
      }
      final service = ref.read(coverArtServiceProvider);
      final bridge = ref.read(rustBridgeServiceProvider);
      return service.resolveCover(
        game,
        steamGridDbApiKey: coverSettings.apiKey,
        coverArtProviderMode: coverSettings.mode,
        coverArtProxyConfig: const CoverArtProxyConfig(),
        rustBridge: bridge,
      );
    });
