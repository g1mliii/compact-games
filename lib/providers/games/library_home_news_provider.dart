import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lifecycle/app_window_visibility.dart';
import '../../core/utils/bounded_list.dart';
import '../../models/game_info.dart';
import '../../models/game_news_item.dart';
import '../../services/steam_news_service.dart';
import '../../services/steam_news_store.dart';
import 'game_catalog_identity_provider.dart';
import 'game_list_provider.dart';
import 'library_home_section_lifecycle.dart';

/// Whether the news shelf may reach the network.
///
/// This is the single seam the master Offline setting will drive; until then
/// networking is allowed. Overriding it to false must leave cached items
/// visible and issue no requests.
final newsNetworkAllowedProvider = Provider<bool>((ref) => true);

final steamNewsStoreProvider = Provider<SteamNewsStore>(
  (ref) => const SteamNewsStore(),
);

final steamNewsServiceProvider = Provider.autoDispose<SteamNewsService>((ref) {
  final service = SteamNewsService(
    identityService: ref.watch(gameCatalogIdentityServiceProvider),
  );
  ref.onDispose(service.shutdown);
  return service;
});

/// Clock seam so freshness and cache-age assertions are testable.
final newsClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

@immutable
class LibraryHomeNewsState {
  const LibraryHomeNewsState({required this.items, required this.isStale});

  static const LibraryHomeNewsState empty = LibraryHomeNewsState(
    items: <GameNewsItem>[],
    isStale: false,
  );

  final List<GameNewsItem> items;

  /// Cached items are being shown because a refresh failed or was skipped.
  final bool isStale;

  bool get hasItems => items.isNotEmpty;

  /// Only staleness ever changes without the items changing with it.
  LibraryHomeNewsState copyWith({required bool isStale}) =>
      LibraryHomeNewsState(items: items, isStale: isStale);
}

/// The Library Home news shelf.
///
/// Auto-disposing on purpose: the provider is only watched while the surface
/// is mounted, so "fetch only while Library Home is visible" needs no explicit
/// visibility tracking beyond the tray check below. There is no polling timer —
/// a refresh happens when the surface appears with a stale cache, and not
/// otherwise.
final libraryHomeNewsProvider =
    AsyncNotifierProvider.autoDispose<
      LibraryHomeNewsNotifier,
      LibraryHomeNewsState
    >(LibraryHomeNewsNotifier.new);

class LibraryHomeNewsNotifier extends AsyncNotifier<LibraryHomeNewsState>
    with LibraryHomeSectionLifecycle<LibraryHomeNewsState> {
  late SteamNewsService _service;

  @override
  Future<LibraryHomeNewsState> build() async {
    armSectionLifecycle();
    // Watching the auto-disposed service ties its request queue to this
    // surface. Leaving Library Home therefore calls shutdown and cancels any
    // candidates that have not started yet.
    _service = ref.watch(steamNewsServiceProvider);

    final store = ref.read(steamNewsStoreProvider);
    final cached = await store.load();
    if (isDisposed) {
      return LibraryHomeNewsState.empty;
    }

    final now = ref.read(newsClockProvider)();
    final visible = cappedTo(cached.items, SteamNewsService.maxVisibleItems);
    final isFresh = cached.isFreshAt(now);

    if (!isFresh) {
      // Paint the cache first, then refresh after the frame so the surface's
      // first appearance is never blocked on the network.
      scheduleRefreshAfterFirstPaint();
    }
    return LibraryHomeNewsState(
      items: visible,
      isStale: !isFresh && visible.isNotEmpty,
    );
  }

  @override
  Future<void> refresh() async {
    if (shouldSkipRefresh) return;
    final current = state.value ?? LibraryHomeNewsState.empty;

    // A window hidden to the tray is not "visible Library Home" no matter what
    // the widget tree still holds. Nothing else re-arms the refresh, so wait for
    // the window to come back rather than leaving the shelf stale until the user
    // navigates away and returns.
    if (appWindowVisibilityController.isHiddenToTray) {
      refreshWhenVisible();
      return;
    }

    if (!ref.read(newsNetworkAllowedProvider)) {
      // Cached items stay on screen; nothing is requested.
      state = AsyncValue.data(current.copyWith(isStale: current.hasItems));
      return;
    }

    final games = ref.read(gameListProvider).value?.games ?? const <GameInfo>[];
    if (games.isEmpty) return;

    final bridge = ref.read(rustBridgeServiceProvider);

    final fetched = await guardedFetch(
      () => _service.refresh(games, rustBridge: bridge),
      fallback: const <GameNewsItem>[],
    );
    if (isDisposed) return;

    if (fetched.isEmpty) {
      // Keep whatever the cache gave us and mark it stale rather than blanking
      // the shelf on a failed refresh.
      state = AsyncValue.data(current.copyWith(isStale: current.hasItems));
      return;
    }

    state = AsyncValue.data(
      LibraryHomeNewsState(items: fetched, isStale: false),
    );

    final now = ref.read(newsClockProvider)();
    await ref.read(steamNewsStoreProvider).save(fetched, now: now);
  }
}
