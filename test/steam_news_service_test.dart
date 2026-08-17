import 'dart:async';
import 'dart:convert';

import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/models/game_news_item.dart';
import 'package:compact_games/services/game_catalog_identity_service.dart';
import 'package:compact_games/services/steam_news_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const int _oneGiB = 1024 * 1024 * 1024;

GameInfo _game({
  required String name,
  required String path,
  int? steamAppId,
  int sizeBytes = _oneGiB,
  DateTime? lastCompressedAt,
  bool isCompressed = false,
  Platform platform = Platform.steam,
}) {
  return GameInfo(
    name: name,
    path: path,
    platform: platform,
    sizeBytes: sizeBytes,
    steamAppId: steamAppId,
    isCompressed: isCompressed,
    compressedSize: isCompressed ? sizeBytes ~/ 2 : null,
    lastCompressedAt: lastCompressedAt,
  );
}

String _newsBody({
  required String gid,
  String title = 'Patch notes',
  String url = 'https://steamcommunity.com/games/1/announcements/detail/1',
  int date = 1780000000,
}) {
  return jsonEncode(<String, dynamic>{
    'appnews': <String, dynamic>{
      'appid': 620,
      'newsitems': <Map<String, dynamic>>[
        <String, dynamic>{
          'gid': gid,
          'title': title,
          'url': url,
          'date': date,
          'feedlabel': 'Community Announcements',
        },
      ],
    },
  });
}

/// Serves canned news responses and tracks concurrency.
class _FakeNewsClient extends http.BaseClient {
  _FakeNewsClient({
    required this.bodyForAppId,
    this.delay = Duration.zero,
    this.statusCode = 200,
    this.throwError = false,
  });

  final String? Function(String appId) bodyForAppId;
  final Duration delay;
  final int statusCode;
  final bool throwError;

  final List<Uri> requests = <Uri>[];
  int _inFlight = 0;
  int peakConcurrency = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    _inFlight += 1;
    peakConcurrency = _inFlight > peakConcurrency ? _inFlight : peakConcurrency;
    try {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (throwError) {
        throw http.ClientException('network down');
      }
      final body = bodyForAppId(request.url.queryParameters['appid'] ?? '');
      if (body == null) {
        return http.StreamedResponse(const Stream<List<int>>.empty(), 404);
      }
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(body)),
        statusCode,
      );
    } finally {
      _inFlight -= 1;
    }
  }
}

SteamNewsService _service(_FakeNewsClient client) {
  final service = SteamNewsService(
    // The identity service is given a client that never matches, so every
    // resolution here comes from the games' native app ids.
    identityService: GameCatalogIdentityService(
      clientFactory: () => _FakeNewsClient(bodyForAppId: (_) => null),
    ),
    clientFactory: () => client,
  );
  addTearDown(service.shutdown);
  return service;
}

void main() {
  group('orderNewsCandidates', () {
    test('recently compressed first, then larger, then path', () {
      final games = <GameInfo>[
        _game(name: 'Big', path: r'C:\b', sizeBytes: 90 * _oneGiB),
        _game(name: 'Small', path: r'C:\s', sizeBytes: 2 * _oneGiB),
        _game(
          name: 'Older',
          path: r'C:\o',
          isCompressed: true,
          lastCompressedAt: DateTime.utc(2026, 1, 1),
        ),
        _game(
          name: 'Newer',
          path: r'C:\n',
          isCompressed: true,
          lastCompressedAt: DateTime.utc(2026, 5, 1),
        ),
      ];

      expect(orderNewsCandidates(games).map((g) => g.name), <String>[
        'Newer',
        'Older',
        'Big',
        'Small',
      ]);
    });

    test('is stable regardless of input order', () {
      final games = <GameInfo>[
        _game(name: 'A', path: r'C:\a', sizeBytes: 5 * _oneGiB),
        _game(name: 'B', path: r'C:\b', sizeBytes: 5 * _oneGiB),
        _game(name: 'C', path: r'C:\c', sizeBytes: 5 * _oneGiB),
      ];

      expect(
        orderNewsCandidates(games).map((g) => g.path),
        orderNewsCandidates(games.reversed.toList()).map((g) => g.path),
      );
    });

    test('caps the candidate list at 16', () {
      final games = <GameInfo>[
        for (var i = 0; i < 50; i++)
          _game(name: 'G$i', path: r'C:\g' + '$i'.padLeft(3, '0')),
      ];

      expect(orderNewsCandidates(games).length, SteamNewsService.maxCandidates);
    });
  });

  group('dedupeAndTrimNews', () {
    GameNewsItem item(String id, String url, int day) => GameNewsItem(
      id: id,
      gamePath: r'C:\g',
      steamAppId: 1,
      title: 'T',
      url: url,
      publishedAt: DateTime.utc(2026, 1, day),
    );

    test('drops repeated ids and repeated urls', () {
      final result = dedupeAndTrimNews(<GameNewsItem>[
        item('a', 'https://steamcommunity.com/1', 3),
        item('a', 'https://steamcommunity.com/2', 2),
        item('b', 'https://steamcommunity.com/1', 1),
        item('c', 'https://steamcommunity.com/3', 4),
      ]);

      expect(result.map((i) => i.id), <String>['c', 'a']);
    });

    test('keeps the newest 12 and orders newest first', () {
      final result = dedupeAndTrimNews(<GameNewsItem>[
        for (var i = 1; i <= 20; i++)
          item('id$i', 'https://steamcommunity.com/$i', i),
      ]);

      expect(result.length, SteamNewsService.maxVisibleItems);
      expect(result.first.id, 'id20');
      expect(result.last.id, 'id9');
    });
  });

  group('parseFirstNewsItem', () {
    final game = _game(name: 'G', path: r'C:\g', steamAppId: 620);

    test('extracts a well-formed item and converts seconds to a date', () {
      final item = parseFirstNewsItem(
        jsonDecode(_newsBody(gid: 'g1', date: 1780000000))
            as Map<String, dynamic>,
        game: game,
        steamAppId: 620,
      );

      expect(item, isNotNull);
      expect(item!.id, 'g1');
      expect(item.steamAppId, 620);
      expect(item.gamePath, r'C:\g');
      expect(
        item.publishedAt,
        DateTime.fromMillisecondsSinceEpoch(1780000000 * 1000, isUtc: true),
      );
    });

    test('sanitizes markup out of the headline', () {
      final item = parseFirstNewsItem(
        jsonDecode(_newsBody(gid: 'g1', title: '[b]Big[/b] <i>news</i>'))
            as Map<String, dynamic>,
        game: game,
        steamAppId: 620,
      );

      expect(item!.title, 'Big news');
    });

    test('rejects an item whose url is not an allowlisted Steam host', () {
      final item = parseFirstNewsItem(
        jsonDecode(_newsBody(gid: 'g1', url: 'https://evil.example.com/x'))
            as Map<String, dynamic>,
        game: game,
        steamAppId: 620,
      );

      expect(item, isNull);
    });

    test('rejects live timestamps outside the persisted-data bounds', () {
      for (final date in <int>[946684799, 4102444801, 8640000000001]) {
        final item = parseFirstNewsItem(
          jsonDecode(_newsBody(gid: 'g1', date: date)) as Map<String, dynamic>,
          game: game,
          steamAppId: 620,
        );

        expect(item, isNull, reason: '$date');
      }
    });

    test('malformed payload shapes return null rather than throwing', () {
      for (final raw in <String>[
        '{}',
        '{"appnews": 5}',
        '{"appnews": {"newsitems": {}}}',
        '{"appnews": {"newsitems": [1, "x"]}}',
        '{"appnews": {"newsitems": [{"gid": "a"}]}}',
        '{"appnews": {"newsitems": [{"gid":"a","title":"t",'
            '"url":"https://steamcommunity.com/1","date":"nope"}]}}',
      ]) {
        expect(
          parseFirstNewsItem(
            jsonDecode(raw) as Map<String, dynamic>,
            game: game,
            steamAppId: 620,
          ),
          isNull,
          reason: raw,
        );
      }
    });
  });

  group('SteamNewsService.refresh', () {
    test('asks for one item per game and returns them newest first', () async {
      final client = _FakeNewsClient(
        bodyForAppId: (appId) => _newsBody(
          gid: 'gid$appId',
          url: 'https://steamcommunity.com/announcements/$appId',
          date: 1780000000 + int.parse(appId),
        ),
      );
      final service = _service(client);

      final items = await service.refresh(<GameInfo>[
        _game(name: 'A', path: r'C:\a', steamAppId: 1),
        _game(name: 'B', path: r'C:\b', steamAppId: 2),
      ]);

      expect(items.length, 2);
      expect(items.first.id, 'gid2');
      for (final uri in client.requests) {
        expect(uri.queryParameters['count'], '1');
        expect(uri.host, 'api.steampowered.com');
      }
    });

    test('games without an identity are skipped, not requested', () async {
      final client = _FakeNewsClient(
        bodyForAppId: (appId) => _newsBody(gid: 'gid$appId'),
      );
      final service = _service(client);

      final items = await service.refresh(<GameInfo>[
        _game(name: 'Known', path: r'C:\a', steamAppId: 1),
        // No native app id, and the identity client resolves nothing.
        _game(name: 'Unknown', path: r'C:\b', platform: Platform.epicGames),
      ]);

      expect(items.length, 1);
      expect(client.requests.length, 1);
    });

    test('never exceeds concurrency 2', () async {
      final client = _FakeNewsClient(
        bodyForAppId: (appId) => _newsBody(gid: 'gid$appId'),
        delay: const Duration(milliseconds: 10),
      );
      final service = _service(client);

      await service.refresh(<GameInfo>[
        for (var i = 1; i <= 8; i++)
          _game(name: 'G$i', path: r'C:\g$i', steamAppId: i),
      ]);

      expect(client.peakConcurrency, lessThanOrEqualTo(2));
      expect(client.peakConcurrency, greaterThan(1));
    });

    test('never requests more than 16 candidates', () async {
      final client = _FakeNewsClient(
        bodyForAppId: (appId) => _newsBody(gid: 'gid$appId'),
      );
      final service = _service(client);

      await service.refresh(<GameInfo>[
        for (var i = 1; i <= 40; i++)
          _game(
            name: 'G$i',
            path: r'C:\g' + '$i'.padLeft(3, '0'),
            steamAppId: i,
          ),
      ]);

      expect(client.requests.length, SteamNewsService.maxCandidates);
    });

    test('caps the returned list at 12 even with more candidates', () async {
      final client = _FakeNewsClient(
        bodyForAppId: (appId) => _newsBody(
          gid: 'gid$appId',
          url: 'https://steamcommunity.com/announcements/$appId',
          date: 1780000000 + int.parse(appId),
        ),
      );
      final service = _service(client);

      final items = await service.refresh(<GameInfo>[
        for (var i = 1; i <= 16; i++)
          _game(
            name: 'G$i',
            path: r'C:\g' + '$i'.padLeft(3, '0'),
            steamAppId: i,
          ),
      ]);

      expect(items.length, SteamNewsService.maxVisibleItems);
    });

    test('duplicate items across games collapse to one', () async {
      // Two games whose feeds report the same announcement.
      final client = _FakeNewsClient(
        bodyForAppId: (_) => _newsBody(gid: 'same'),
      );
      final service = _service(client);

      final items = await service.refresh(<GameInfo>[
        _game(name: 'A', path: r'C:\a', steamAppId: 1),
        _game(name: 'B', path: r'C:\b', steamAppId: 2),
      ]);

      expect(items.length, 1);
    });

    test('transport errors and non-200 responses yield no items', () async {
      final throwing = _FakeNewsClient(
        bodyForAppId: (_) => _newsBody(gid: 'x'),
        throwError: true,
      );
      expect(
        await _service(
          throwing,
        ).refresh(<GameInfo>[_game(name: 'A', path: r'C:\a', steamAppId: 1)]),
        isEmpty,
      );

      final failing = _FakeNewsClient(
        bodyForAppId: (_) => _newsBody(gid: 'x'),
        statusCode: 503,
      );
      expect(
        await _service(
          failing,
        ).refresh(<GameInfo>[_game(name: 'A', path: r'C:\a', steamAppId: 1)]),
        isEmpty,
      );
    });

    test('malformed bodies yield no items rather than throwing', () async {
      final client = _FakeNewsClient(bodyForAppId: (_) => 'not json at all');
      expect(
        await _service(
          client,
        ).refresh(<GameInfo>[_game(name: 'A', path: r'C:\a', steamAppId: 1)]),
        isEmpty,
      );
    });

    test('one invalid timestamp does not discard other games', () async {
      final client = _FakeNewsClient(
        bodyForAppId: (appId) => _newsBody(
          gid: 'gid$appId',
          date: appId == '1' ? 8640000000001 : 1780000000,
        ),
      );
      final service = _service(client);

      final items = await service.refresh(<GameInfo>[
        _game(name: 'Invalid', path: r'C:\invalid', steamAppId: 1),
        _game(name: 'Valid', path: r'C:\valid', steamAppId: 2),
      ]);

      expect(items.map((item) => item.id), <String>['gid2']);
    });

    test('an empty library performs no work', () async {
      final client = _FakeNewsClient(bodyForAppId: (_) => _newsBody(gid: 'x'));
      final service = _service(client);

      expect(await service.refresh(const <GameInfo>[]), isEmpty);
      expect(client.requests, isEmpty);
    });

    test('shutdown mid-flight discards results and stops the queue', () async {
      final client = _FakeNewsClient(
        bodyForAppId: (appId) => _newsBody(gid: 'gid$appId'),
        delay: const Duration(milliseconds: 30),
      );
      final service = SteamNewsService(
        identityService: GameCatalogIdentityService(
          clientFactory: () => _FakeNewsClient(bodyForAppId: (_) => null),
        ),
        clientFactory: () => client,
      );

      final pending = service.refresh(<GameInfo>[
        for (var i = 1; i <= 10; i++)
          _game(name: 'G$i', path: r'C:\g$i', steamAppId: i),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.shutdown();

      expect(await pending, isEmpty);
      // The queue stopped early rather than draining all ten candidates.
      expect(client.requests.length, lessThan(10));
    });
  });
}
