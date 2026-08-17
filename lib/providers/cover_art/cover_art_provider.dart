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

final coverArtProxyConfigProvider = Provider<CoverArtProxyConfig>(
  (ref) => const CoverArtProxyConfig(),
);

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
      final game = ref.read(singleGameProvider(gamePath));
      if (game == null) {
        return const CoverArtResult.none();
      }
      final service = ref.read(coverArtServiceProvider);
      final bridge = ref.read(rustBridgeServiceProvider);
      final proxyConfig = ref.read(coverArtProxyConfigProvider);

      // Capture resolution dependencies before the async settings wait because
      // the provider may rebuild while the settings future is pending.
      final settingsState = await ref.watch(settingsProvider.future);
      final coverSettings = (
        apiKey: settingsState.settings.steamGridDbApiKey,
        mode: settingsState.settings.coverArtProviderMode,
      );

      return service.resolveCover(
        game,
        steamGridDbApiKey: coverSettings.apiKey,
        coverArtProviderMode: coverSettings.mode,
        coverArtProxyConfig: proxyConfig,
        rustBridge: bridge,
      );
    });

/// The cover already in memory for a game, without resolving one.
///
/// Watch this instead of [coverArtProvider] on a surface where artwork is a
/// nicety rather than the point. [coverArtProvider] resolves on first watch —
/// disk probing, Steam `librarycache` scanning, and potentially SteamGridDB or
/// Steam store requests — so a list of a dozen incidental thumbnails would turn
/// opening that surface into a dozen cover lookups.
///
/// Resolves to null until the settings load, and re-reads whenever the surface
/// remounts; it does not observe the cache filling underneath it.
final cachedCoverArtProvider = Provider.autoDispose
    .family<CoverArtResult?, String>((ref, gamePath) {
      final settingsState = ref.watch(settingsProvider).value;
      if (settingsState == null) {
        return null;
      }
      return ref
          .read(coverArtServiceProvider)
          .peekCachedCover(
            gamePath,
            steamGridDbApiKey: settingsState.settings.steamGridDbApiKey,
            coverArtProviderMode: settingsState.settings.coverArtProviderMode,
            coverArtProxyConfig: ref.read(coverArtProxyConfigProvider),
          );
    });
