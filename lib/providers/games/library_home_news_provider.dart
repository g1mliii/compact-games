import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lifecycle/app_window_visibility.dart';
import '../../models/game_info.dart';
import '../../models/game_news_item.dart';
import '../../services/steam_news_service.dart';
import '../../services/steam_news_store.dart';
import 'game_list_provider.dart';

/// Whether the news shelf may reach the network.
///
/// This is the single seam the master Offline setting will drive; until then
/// networking is allowed. Overriding it to false must leave cached items
/// visible and issue no requests.
final newsNetworkAllowedProvider = Provider<bool>((ref) => true);

final steamNewsStoreProvider = Provider<SteamNewsStore>(
  (ref) => const SteamNewsStore(),
);

final steamNewsServiceProvider = Provider<SteamNewsService>((ref) {
  final service = SteamNewsService();
  ref.onDispose(service.shutdown);
  return service;
});

/// Clock seam so freshness and cache-age assertions are testable.
final newsClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

@immutable
class LibraryHomeNewsState {
  const LibraryHomeNewsState({
    required this.items,
    required this.isStale,
    required this.isRefreshing,
  });

  static const LibraryHomeNewsState empty = LibraryHomeNewsState(
    items: <GameNewsItem>[],
    isStale: false,
    isRefreshing: false,
  );

  final List<GameNewsItem> items;

  /// Cached items are being shown because a refresh failed or was skipped.
  final bool isStale;

  final bool isRefreshing;

  bool get hasItems => items.isNotEmpty;

  LibraryHomeNewsState copyWith({
    List<GameNewsItem>? items,
    bool? isStale,
    bool? isRefreshing,
  }) {
    return LibraryHomeNewsState(
      items: items ?? this.items,
      isStale: isStale ?? this.isStale,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
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

class LibraryHomeNewsNotifier extends AsyncNotifier<LibraryHomeNewsState> {
  var _disposed = false;

  @override
  Future<LibraryHomeNewsState> build() async {
    ref.onDispose(() => _disposed = true);

    final store = ref.read(steamNewsStoreProvider);
    final cached = await store.load();
    if (_disposed) {
      return LibraryHomeNewsState.empty;
    }

    final now = ref.read(newsClockProvider)();
    final visible = cached.items.length > SteamNewsService.maxVisibleItems
        ? cached.items.sublist(0, SteamNewsService.maxVisibleItems)
        : cached.items;

    if (cached.isFreshAt(now)) {
      return LibraryHomeNewsState(
        items: visible,
        isStale: false,
        isRefreshing: false,
      );
    }

    // Paint the cache first, then refresh after the frame so the surface's
    // first appearance is never blocked on the network.
    _scheduleRefreshAfterFirstPaint();
    return LibraryHomeNewsState(
      items: visible,
      isStale: visible.isNotEmpty,
      isRefreshing: false,
    );
  }

  void _scheduleRefreshAfterFirstPaint() {
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) {
      if (_disposed) return;
      unawaited(refresh());
    });
    // A post-frame callback only fires if another frame is scheduled; ask for
    // one so a static surface still triggers the refresh.
    binding.scheduleFrame();
  }

  /// Refreshes from the network when allowed. Safe to call redundantly.
  Future<void> refresh() async {
    if (_disposed) return;

    final current = state.value ?? LibraryHomeNewsState.empty;
    if (current.isRefreshing) return;

    // A window hidden to the tray is not "visible Library Home" no matter what
    // the widget tree still holds.
    if (appWindowVisibilityController.isHiddenToTray) return;

    if (!ref.read(newsNetworkAllowedProvider)) {
      // Cached items stay on screen; nothing is requested.
      state = AsyncValue.data(
        current.copyWith(isStale: current.hasItems, isRefreshing: false),
      );
      return;
    }

    final games = ref.read(gameListProvider).value?.games ?? const <GameInfo>[];
    if (games.isEmpty) return;

    state = AsyncValue.data(current.copyWith(isRefreshing: true));

    final service = ref.read(steamNewsServiceProvider);
    final bridge = ref.read(rustBridgeServiceProvider);

    List<GameNewsItem> fetched;
    try {
      fetched = await service.refresh(games, rustBridge: bridge);
    } catch (_) {
      fetched = const <GameNewsItem>[];
    }
    if (_disposed) return;

    if (fetched.isEmpty) {
      // Keep whatever the cache gave us and mark it stale rather than blanking
      // the shelf on a failed refresh.
      state = AsyncValue.data(
        current.copyWith(isStale: current.hasItems, isRefreshing: false),
      );
      return;
    }

    state = AsyncValue.data(
      LibraryHomeNewsState(items: fetched, isStale: false, isRefreshing: false),
    );

    final now = ref.read(newsClockProvider)();
    await ref.read(steamNewsStoreProvider).save(fetched, now: now);
  }
}
