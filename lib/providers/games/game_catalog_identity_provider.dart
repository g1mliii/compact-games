import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/game_catalog_identity_service.dart';

/// The app's one by-name Steam catalog lookup.
///
/// Deliberately not auto-disposed, unlike the feature services that use it.
/// Which app id a game is, is app-wide knowledge that does not change while the
/// app runs, and every consumer resolves the same size-ordered library: giving
/// the news shelf and the players panel a service each meant two caches asking
/// Steam the same questions, and tying the cache to an auto-disposed provider
/// meant throwing both away — negative results included — every time the user
/// left Library Home.
final gameCatalogIdentityServiceProvider = Provider<GameCatalogIdentityService>(
  (ref) {
    final service = GameCatalogIdentityService();
    ref.onDispose(service.shutdown);
    return service;
  },
);
