import 'package:compact_games/core/lifecycle/app_window_visibility.dart';
import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/models/game_news_item.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/games/library_home_news_provider.dart';
import 'package:compact_games/services/steam_news_service.dart';
import 'package:compact_games/services/steam_news_store.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/noop_rust_bridge_service.dart';

const int _oneGiB = 1024 * 1024 * 1024;

final List<GameInfo> _games = <GameInfo>[
  GameInfo(
    name: 'Pixel Raider',
    path: r'C:\Games\pixel_raider',
    platform: Platform.steam,
    sizeBytes: 96 * _oneGiB,
    steamAppId: 620,
  ),
];

class _GamesBridgeService extends NoOpRustBridgeService {
  const _GamesBridgeService();

  @override
  Future<List<GameInfo>> getAllGames() async => _games;
  @override
  Future<List<GameInfo>> getAllGamesQuick() async => _games;
  @override
  Future<List<GameInfo>> refreshAllGames() async => _games;
}

GameNewsItem _item(String id, {DateTime? at}) => GameNewsItem(
  id: id,
  gamePath: r'C:\Games\pixel_raider',
  steamAppId: 620,
  title: 'Headline $id',
  url: 'https://steamcommunity.com/announcements/$id',
  publishedAt: at ?? DateTime.utc(2026, 5, 1),
);

/// In-memory store so tests never touch SharedPreferences.
class _FakeStore implements SteamNewsStore {
  _FakeStore({this.snapshot = CachedNewsSnapshot.empty});

  CachedNewsSnapshot snapshot;
  int saveCount = 0;
  List<GameNewsItem>? lastSaved;

  @override
  Future<CachedNewsSnapshot> load() async => snapshot;

  @override
  Future<void> save(List<GameNewsItem> items, {required DateTime now}) async {
    saveCount += 1;
    lastSaved = items;
    snapshot = CachedNewsSnapshot(items: items, fetchedAt: now);
  }

  @override
  Future<void> clear() async {
    snapshot = CachedNewsSnapshot.empty;
  }
}

/// Records refresh calls and returns a scripted result.
class _FakeNewsService implements SteamNewsService {
  _FakeNewsService({this.result = const <GameNewsItem>[]});

  List<GameNewsItem> result;
  int refreshCount = 0;

  @override
  Future<List<GameNewsItem>> refresh(
    List<GameInfo> games, {
    Object? rustBridge,
  }) async {
    refreshCount += 1;
    return result;
  }

  @override
  void shutdown() {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container({
  required _FakeStore store,
  required _FakeNewsService service,
  bool networkAllowed = true,
  DateTime? now,
}) {
  final container = ProviderContainer(
    overrides: [
      rustBridgeServiceProvider.overrideWithValue(const _GamesBridgeService()),
      steamNewsStoreProvider.overrideWithValue(store),
      steamNewsServiceProvider.overrideWithValue(service),
      newsNetworkAllowedProvider.overrideWithValue(networkAllowed),
      newsClockProvider.overrideWithValue(
        () => now ?? DateTime.utc(2026, 5, 1, 12),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Mounts the shelf and drives the post-frame callback the notifier uses to
/// defer its first fetch.
///
/// The provider auto-disposes, so the subscription is what stands in for "the
/// Library Home surface is on screen" — without it the notifier is torn down
/// between reads exactly as it would be when the surface unmounts.
Future<void> _settle(ProviderContainer container) async {
  await container.read(gameListProvider.future);
  final subscription = container.listen(
    libraryHomeNewsProvider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);

  await container.read(libraryHomeNewsProvider.future);
  SchedulerBinding.instance.handleBeginFrame(Duration.zero);
  SchedulerBinding.instance.handleDrawFrame();
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(appWindowVisibilityController.markVisible);

  test('a fresh cache paints immediately and issues no refresh', () async {
    final store = _FakeStore(
      snapshot: CachedNewsSnapshot(
        items: <GameNewsItem>[_item('a')],
        fetchedAt: DateTime.utc(2026, 5, 1, 11),
      ),
    );
    final service = _FakeNewsService(result: <GameNewsItem>[_item('fresh')]);
    final container = _container(store: store, service: service);

    await _settle(container);

    final state = container.read(libraryHomeNewsProvider).value!;
    expect(state.items.map((i) => i.id), <String>['a']);
    expect(state.isStale, isFalse);
    expect(service.refreshCount, 0);
  });

  test(
    'a stale cache is shown, then replaced by a successful refresh',
    () async {
      final store = _FakeStore(
        snapshot: CachedNewsSnapshot(
          items: <GameNewsItem>[_item('old')],
          // Well outside the six hour window.
          fetchedAt: DateTime.utc(2026, 4, 1),
        ),
      );
      final service = _FakeNewsService(result: <GameNewsItem>[_item('new')]);
      final container = _container(store: store, service: service);

      await _settle(container);

      final state = container.read(libraryHomeNewsProvider).value!;
      expect(service.refreshCount, 1);
      expect(state.items.map((i) => i.id), <String>['new']);
      expect(state.isStale, isFalse);
      expect(store.saveCount, 1);
    },
  );

  test('a failed refresh keeps cached items and marks them stale', () async {
    final store = _FakeStore(
      snapshot: CachedNewsSnapshot(
        items: <GameNewsItem>[_item('old')],
        fetchedAt: DateTime.utc(2026, 4, 1),
      ),
    );
    // An empty result stands in for offline, timeout, and malformed responses
    // alike — the service already collapses all three to "no news".
    final service = _FakeNewsService();
    final container = _container(store: store, service: service);

    await _settle(container);

    final state = container.read(libraryHomeNewsProvider).value!;
    expect(service.refreshCount, 1);
    expect(state.items.map((i) => i.id), <String>['old']);
    expect(state.isStale, isTrue);
    // A failed refresh must not overwrite the cache with nothing.
    expect(store.saveCount, 0);
  });

  test('networking disabled shows the cache and requests nothing', () async {
    final store = _FakeStore(
      snapshot: CachedNewsSnapshot(
        items: <GameNewsItem>[_item('cached')],
        fetchedAt: DateTime.utc(2026, 4, 1),
      ),
    );
    final service = _FakeNewsService(result: <GameNewsItem>[_item('new')]);
    final container = _container(
      store: store,
      service: service,
      networkAllowed: false,
    );

    await _settle(container);

    final state = container.read(libraryHomeNewsProvider).value!;
    expect(service.refreshCount, 0);
    expect(state.items.map((i) => i.id), <String>['cached']);
    expect(state.isStale, isTrue);
  });

  test('a window hidden to the tray does not refresh', () async {
    final store = _FakeStore(
      snapshot: CachedNewsSnapshot(
        items: <GameNewsItem>[_item('cached')],
        fetchedAt: DateTime.utc(2026, 4, 1),
      ),
    );
    final service = _FakeNewsService(result: <GameNewsItem>[_item('new')]);
    final container = _container(store: store, service: service);

    appWindowVisibilityController.markHiddenToTray();
    await _settle(container);

    expect(service.refreshCount, 0);
    expect(
      container.read(libraryHomeNewsProvider).value!.items.map((i) => i.id),
      <String>['cached'],
    );
  });

  test('an empty cache with no results leaves the shelf empty', () async {
    final store = _FakeStore();
    final service = _FakeNewsService();
    final container = _container(store: store, service: service);

    await _settle(container);

    final state = container.read(libraryHomeNewsProvider).value!;
    expect(state.hasItems, isFalse);
    expect(state.isStale, isFalse);
  });

  test('a cached payload is trimmed to the visible cap', () async {
    final store = _FakeStore(
      snapshot: CachedNewsSnapshot(
        items: <GameNewsItem>[
          for (var i = 0; i < 24; i++)
            _item('id$i', at: DateTime.utc(2026, 5, 1, 12 - i)),
        ],
        fetchedAt: DateTime.utc(2026, 5, 1, 11),
      ),
    );
    final container = _container(store: store, service: _FakeNewsService());

    await _settle(container);

    expect(
      container.read(libraryHomeNewsProvider).value!.items.length,
      SteamNewsService.maxVisibleItems,
    );
  });
}
