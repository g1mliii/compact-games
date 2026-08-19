import 'package:compact_games/core/config/cover_art_proxy_config.dart';
import 'package:compact_games/models/app_settings.dart';
import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/models/game_news_item.dart';
import 'package:compact_games/models/game_player_count.dart';
import 'package:compact_games/providers/cover_art/cover_art_provider.dart';
import 'package:compact_games/providers/games/library_home_news_provider.dart';
import 'package:compact_games/providers/games/library_home_players_provider.dart';
import 'package:compact_games/services/cover_art_service.dart';
import 'package:compact_games/services/steam_news_service.dart';
import 'package:compact_games/services/steam_news_store.dart';
import 'package:compact_games/services/steam_player_count_service.dart';

import 'noop_rust_bridge_service.dart';

/// Keeps a Library Home widget test off the network and off the disk.
///
/// Both of the surface's sections fetch as soon as they mount — news on one
/// side, live player counts on the other — and every row of both paints cover
/// art. A test that pumps the surface without these is quietly issuing real
/// requests to Steam and probing the machine's Steam install for artwork.
///
/// Pass a double for whichever piece the test is actually about; the rest
/// answer with nothing.
// Riverpod 3 does not export the name of an override's type, so the return
// type can only come from inference.
// ignore: strict_top_level_inference
libraryHomeOfflineOverrides({
  SteamNewsStore? newsStore,
  SteamNewsService? newsService,
  SteamPlayerCountService? playerCountService,
  CoverArtService? coverArtService,
}) {
  final players = playerCountService ?? IdlePlayerCountService();
  final news = newsService ?? IdleNewsService();
  return [
    coverArtServiceProvider.overrideWithValue(
      coverArtService ?? NoCoverArtService(),
    ),
    steamNewsStoreProvider.overrideWithValue(newsStore ?? EmptyNewsStore()),
    steamNewsServiceProvider.overrideWith((ref) {
      ref.onDispose(news.shutdown);
      return news;
    }),
    steamPlayerCountServiceProvider.overrideWith((ref) {
      ref.onDispose(players.shutdown);
      return players;
    }),
  ];
}

/// A cache with nothing in it, and no interest in what is saved to it.
class EmptyNewsStore implements SteamNewsStore {
  @override
  Future<CachedNewsSnapshot> load() async => CachedNewsSnapshot.empty;

  @override
  Future<void> save(List<GameNewsItem> items, {required DateTime now}) async {}
}

class IdleNewsService implements SteamNewsService {
  int refreshCount = 0;
  int shutdownCount = 0;

  @override
  Future<List<GameNewsItem>> refresh(
    List<GameInfo> games, {
    Object? rustBridge,
  }) async {
    refreshCount += 1;
    return const <GameNewsItem>[];
  }

  @override
  void shutdown() {
    shutdownCount += 1;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class IdlePlayerCountService implements SteamPlayerCountService {
  int refreshCount = 0;
  int shutdownCount = 0;

  @override
  Future<List<GamePlayerCount>> refresh(
    List<GameInfo> games, {
    Object? rustBridge,
  }) async {
    refreshCount += 1;
    return const <GamePlayerCount>[];
  }

  @override
  void shutdown() {
    shutdownCount += 1;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Resolves no artwork, so a test never waits on disk probing or a download.
class NoCoverArtService implements CoverArtService {
  @override
  CoverArtResult? peekCachedCover(
    String gamePath, {
    String? steamGridDbApiKey,
    CoverArtProviderMode coverArtProviderMode =
        CoverArtProviderMode.bundledProxy,
    CoverArtProxyConfig coverArtProxyConfig = const CoverArtProxyConfig(),
  }) => null;

  @override
  Future<CoverArtResult> resolveCover(
    GameInfo game, {
    String? steamGridDbApiKey,
    CoverArtProviderMode coverArtProviderMode =
        CoverArtProviderMode.bundledProxy,
    CoverArtProxyConfig coverArtProxyConfig = const CoverArtProxyConfig(),
    Object? rustBridge,
  }) async => const CoverArtResult.none();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A bridge that answers every game query with [games].
///
/// Library Home reads the game list before either of its sections fetches
/// anything, so a test that wants them to run has to hand one over.
class GamesBridgeService extends NoOpRustBridgeService {
  const GamesBridgeService(this.games);

  final List<GameInfo> games;

  @override
  Future<List<GameInfo>> getAllGames() async => games;

  @override
  Future<List<GameInfo>> getAllGamesQuick() async => games;

  @override
  Future<List<GameInfo>> refreshAllGames() async => games;
}
