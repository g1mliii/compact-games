import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lifecycle/app_window_visibility.dart';
import '../../models/game_info.dart';
import '../../models/game_player_count.dart';
import '../../services/steam_player_count_service.dart';
import 'game_catalog_identity_provider.dart';
import 'game_list_provider.dart';
import 'library_home_section_lifecycle.dart';

/// Whether the player-count panel may reach the network. The same seam the news
/// shelf has, and the one a master Offline setting will drive.
final playerCountsNetworkAllowedProvider = Provider<bool>((ref) => true);

final steamPlayerCountServiceProvider =
    Provider.autoDispose<SteamPlayerCountService>((ref) {
      final service = SteamPlayerCountService(
        identityService: ref.watch(gameCatalogIdentityServiceProvider),
      );
      ref.onDispose(service.shutdown);
      return service;
    });

/// Clock seam, so freshness is testable without waiting.
final playerCountClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Last counts and when they were taken.
///
/// Memory only, and deliberately not auto-disposed: leaving Library Home and
/// coming back within the freshness window should repaint the numbers rather
/// than blank the panel and ask Steam again. Nothing here is written to disk —
/// a "playing now" figure is worthless a day later.
class PlayerCountCache {
  List<GamePlayerCount> items = const <GamePlayerCount>[];
  DateTime? fetchedAt;

  /// How long a count is worth showing before it is refetched.
  static const Duration freshness = Duration(minutes: 5);

  bool isFreshAt(DateTime now) {
    final at = fetchedAt;
    if (at == null) {
      return false;
    }
    final age = now.difference(at);
    return !age.isNegative && age <= freshness;
  }

  void save(List<GamePlayerCount> counts, {required DateTime now}) {
    items = counts;
    fetchedAt = now;
  }
}

final playerCountCacheProvider = Provider<PlayerCountCache>(
  (ref) => PlayerCountCache(),
);

@immutable
class LibraryHomePlayersState {
  const LibraryHomePlayersState({required this.items, required this.isStale});

  final List<GamePlayerCount> items;

  /// Numbers from an earlier fetch are on screen because a refresh failed or
  /// was skipped.
  final bool isStale;

  bool get hasItems => items.isNotEmpty;

  LibraryHomePlayersState copyWith({required bool isStale}) =>
      LibraryHomePlayersState(items: items, isStale: isStale);
}

/// The Library Home "playing now" panel.
///
/// Auto-disposing, so mounting the panel is what scopes the requests to
/// "Library Home is on screen". There is no polling timer: a refresh happens
/// when the surface appears with a stale cache, and not otherwise.
final libraryHomePlayersProvider =
    AsyncNotifierProvider.autoDispose<
      LibraryHomePlayersNotifier,
      LibraryHomePlayersState
    >(LibraryHomePlayersNotifier.new);

class LibraryHomePlayersNotifier extends AsyncNotifier<LibraryHomePlayersState>
    with LibraryHomeSectionLifecycle<LibraryHomePlayersState> {
  late SteamPlayerCountService _service;

  @override
  Future<LibraryHomePlayersState> build() async {
    armSectionLifecycle();
    _service = ref.watch(steamPlayerCountServiceProvider);

    final cache = ref.read(playerCountCacheProvider);
    final now = ref.read(playerCountClockProvider)();
    final isFresh = cache.isFreshAt(now);

    if (!isFresh) {
      // Paint whatever is remembered first, then refresh after the frame, so
      // opening Library Home is never blocked on the network.
      scheduleRefreshAfterFirstPaint();
    }
    return LibraryHomePlayersState(
      items: cache.items,
      isStale: !isFresh && cache.items.isNotEmpty,
    );
  }

  @override
  Future<void> refresh() async {
    if (shouldSkipRefresh) return;

    // The cache, not [state], is the fallback: the first refresh is scheduled
    // from inside `build`, so it can run before the build future has published
    // anything, and reading a null state there would throw away the very
    // numbers this is meant to keep on screen.
    final cache = ref.read(playerCountCacheProvider);
    final current =
        state.value ??
        LibraryHomePlayersState(
          items: cache.items,
          isStale: cache.items.isNotEmpty,
        );

    // Hidden to the tray is not "Library Home is visible", whatever the widget
    // tree still holds.
    if (appWindowVisibilityController.isHiddenToTray) {
      refreshWhenVisible();
      return;
    }

    if (!ref.read(playerCountsNetworkAllowedProvider)) {
      state = AsyncValue.data(current.copyWith(isStale: current.hasItems));
      return;
    }

    final games = ref.read(gameListProvider).value?.games ?? const <GameInfo>[];
    if (games.isEmpty) return;

    final bridge = ref.read(rustBridgeServiceProvider);

    final fetched = await guardedFetch(
      () => _service.refresh(games, rustBridge: bridge),
      fallback: const <GamePlayerCount>[],
    );
    if (isDisposed) return;

    if (fetched.isEmpty) {
      // Keep the last numbers and mark them stale rather than blanking the
      // panel on a failed refresh.
      state = AsyncValue.data(current.copyWith(isStale: current.hasItems));
      return;
    }

    final now = ref.read(playerCountClockProvider)();
    cache.save(fetched, now: now);
    state = AsyncValue.data(
      LibraryHomePlayersState(items: fetched, isStale: false),
    );
  }
}
