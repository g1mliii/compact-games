import 'dart:convert';

import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/services/game_catalog_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Records every request and replays a canned storesearch payload.
class _FakeStoreClient extends http.BaseClient {
  _FakeStoreClient({
    this.items = const <Map<String, Object?>>[],
    this.statusCode = 200,
    this.rawBody,
    this.throwError = false,
  });

  final List<Map<String, Object?>> items;
  final int statusCode;
  final String? rawBody;
  final bool throwError;

  final List<Uri> requests = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    if (throwError) {
      throw http.ClientException('network down');
    }
    final body = rawBody ?? jsonEncode(<String, Object?>{'items': items});
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

GameInfo _game({
  required String name,
  String path = r'C:\Games\game',
  Platform platform = Platform.epicGames,
  int? steamAppId,
}) {
  return GameInfo(
    name: name,
    path: path,
    platform: platform,
    sizeBytes: 1024,
    steamAppId: steamAppId,
  );
}

Future<GameCatalogIdentity> _resolveAgainst(
  _FakeStoreClient client,
  GameInfo game, {
  bool allowNetwork = true,
}) async {
  final service = GameCatalogIdentityService(clientFactory: () => client);
  addTearDown(service.shutdown);
  return service.resolve(game, allowNetwork: allowNetwork);
}

void main() {
  group('foldGameTitle', () {
    test('lowercases and collapses punctuation to single spaces', () {
      expect(
        foldGameTitle('Half-Life 2: Episode One'),
        'half life 2 episode one',
      );
      expect(foldGameTitle('  Portal   2  '), 'portal 2');
      expect(foldGameTitle('S.T.A.L.K.E.R.'), 's t a l k e r');
    });

    test('strips diacritics so accented titles compare equal', () {
      expect(foldGameTitle('Pokémon'), foldGameTitle('Pokemon'));
      expect(foldGameTitle('Æon Flux'), 'aeon flux');
      expect(foldGameTitle('Cœur'), 'coeur');
    });

    test('drops characters with no ascii fold rather than keeping them', () {
      // Non-latin scripts fold away entirely; the caller must treat an empty
      // fold as "no identity" rather than matching everything.
      expect(foldGameTitle('原神'), '');
      expect(foldGameTitle('!!!'), '');
    });

    test('is stable across the separators launchers actually emit', () {
      const expected = 'marvel s spider man remastered';
      expect(foldGameTitle("Marvel's Spider-Man Remastered"), expected);
      expect(foldGameTitle('Marvel’s Spider‑Man Remastered'), expected);
    });
  });

  group('GameCatalogIdentityService.resolve', () {
    test('a native app id short-circuits before any network work', () async {
      final client = _FakeStoreClient();
      final identity = await _resolveAgainst(
        client,
        _game(name: 'Anything', steamAppId: 220),
      );

      expect(identity.steamAppId, 220);
      expect(identity.source, GameCatalogIdentitySource.nativeAppId);
      expect(client.requests, isEmpty);
    });

    test('an exact folded match is accepted', () async {
      final client = _FakeStoreClient(
        items: const <Map<String, Object?>>[
          <String, Object?>{'id': 620, 'name': 'Portal 2'},
        ],
      );
      final identity = await _resolveAgainst(client, _game(name: 'Portal 2'));

      expect(identity.steamAppId, 620);
      expect(identity.source, GameCatalogIdentitySource.strictCatalogMatch);
    });

    test('punctuation and accent differences still count as exact', () async {
      final client = _FakeStoreClient(
        items: const <Map<String, Object?>>[
          <String, Object?>{'id': 1, 'name': "Marvel’s Spider-Man Remastered"},
        ],
      );
      final identity = await _resolveAgainst(
        client,
        _game(name: "Marvel's Spider Man Remastered"),
      );

      expect(identity.steamAppId, 1);
      expect(identity.source, GameCatalogIdentitySource.strictCatalogMatch);
    });

    test('a prefix match is rejected', () async {
      // The cover-art lookup would accept this; news must not.
      final client = _FakeStoreClient(
        items: const <Map<String, Object?>>[
          <String, Object?>{'id': 620, 'name': 'Portal 2'},
        ],
      );
      final identity = await _resolveAgainst(client, _game(name: 'Portal'));

      expect(identity.steamAppId, isNull);
      expect(identity.source, GameCatalogIdentitySource.none);
    });

    test('a contains match is rejected', () async {
      final client = _FakeStoreClient(
        items: const <Map<String, Object?>>[
          <String, Object?>{
            'id': 2,
            'name': 'The Witcher 3: Wild Hunt - Game of the Year Edition',
          },
        ],
      );
      final identity = await _resolveAgainst(
        client,
        _game(name: 'The Witcher 3 Wild Hunt'),
      );

      expect(identity.steamAppId, isNull);
      expect(identity.source, GameCatalogIdentitySource.none);
    });

    test('a fuzzy/near match is rejected', () async {
      final client = _FakeStoreClient(
        items: const <Map<String, Object?>>[
          <String, Object?>{'id': 3, 'name': 'Fallout 4'},
        ],
      );
      final identity = await _resolveAgainst(client, _game(name: 'Fallout 3'));

      expect(identity.steamAppId, isNull);
      expect(identity.source, GameCatalogIdentitySource.none);
    });

    test('the exact match wins even when listed after near misses', () async {
      final client = _FakeStoreClient(
        items: const <Map<String, Object?>>[
          <String, Object?>{'id': 10, 'name': 'DOOM Eternal'},
          <String, Object?>{'id': 11, 'name': 'DOOM Eternal: Deluxe'},
          <String, Object?>{'id': 12, 'name': 'DOOM'},
        ],
      );
      final identity = await _resolveAgainst(client, _game(name: 'DOOM'));

      expect(identity.steamAppId, 12);
    });

    test('malformed payloads resolve to unknown instead of throwing', () async {
      for (final body in <String>['not json', '[]', '{"items": {}}', '']) {
        final client = _FakeStoreClient(rawBody: body);
        final identity = await _resolveAgainst(client, _game(name: 'Whatever'));
        expect(identity.source, GameCatalogIdentitySource.none, reason: body);
      }
    });

    test('non-200 responses and transport errors resolve to unknown', () async {
      final failing = _FakeStoreClient(statusCode: 503);
      expect(
        (await _resolveAgainst(failing, _game(name: 'Some Game'))).source,
        GameCatalogIdentitySource.none,
      );

      final throwing = _FakeStoreClient(throwError: true);
      expect(
        (await _resolveAgainst(throwing, _game(name: 'Some Game'))).source,
        GameCatalogIdentitySource.none,
      );
    });

    test('items missing an id or name are skipped, not matched', () async {
      final client = _FakeStoreClient(
        items: const <Map<String, Object?>>[
          <String, Object?>{'name': 'Portal 2'},
          <String, Object?>{'id': 0, 'name': 'Portal 2'},
          <String, Object?>{'id': 620},
        ],
      );
      final identity = await _resolveAgainst(client, _game(name: 'Portal 2'));

      expect(identity.source, GameCatalogIdentitySource.none);
    });

    test('a title that folds to nothing never reaches the network', () async {
      final client = _FakeStoreClient();
      final identity = await _resolveAgainst(client, _game(name: '!!!'));

      expect(identity.source, GameCatalogIdentitySource.none);
      expect(client.requests, isEmpty);
    });

    test('allowNetwork: false performs no request and is not cached', () async {
      final client = _FakeStoreClient(
        items: const <Map<String, Object?>>[
          <String, Object?>{'id': 620, 'name': 'Portal 2'},
        ],
      );
      final service = GameCatalogIdentityService(clientFactory: () => client);
      addTearDown(service.shutdown);

      final offline = await service.resolve(
        _game(name: 'Portal 2'),
        allowNetwork: false,
      );
      expect(offline.source, GameCatalogIdentitySource.none);
      expect(client.requests, isEmpty);
      expect(service.debugCacheSize, 0);

      // Coming back online must still be able to resolve it.
      final online = await service.resolve(
        _game(name: 'Portal 2'),
        allowNetwork: true,
      );
      expect(online.steamAppId, 620);
    });

    test('repeat lookups reuse the cache, including misses', () async {
      final client = _FakeStoreClient(
        items: const <Map<String, Object?>>[
          <String, Object?>{'id': 620, 'name': 'Portal 2'},
        ],
      );
      final service = GameCatalogIdentityService(clientFactory: () => client);
      addTearDown(service.shutdown);

      await service.resolve(_game(name: 'Portal 2'), allowNetwork: true);
      await service.resolve(_game(name: 'Portal 2'), allowNetwork: true);
      // A title with no catalog entry is also asked about only once.
      await service.resolve(_game(name: 'Unlisted Thing'), allowNetwork: true);
      await service.resolve(_game(name: 'Unlisted Thing'), allowNetwork: true);

      expect(client.requests.length, 2);
      expect(service.debugCacheSize, 2);
    });

    test('shutdown drops the cache so lookups start clean', () async {
      final client = _FakeStoreClient(
        items: const <Map<String, Object?>>[
          <String, Object?>{'id': 620, 'name': 'Portal 2'},
        ],
      );
      final service = GameCatalogIdentityService(clientFactory: () => client);

      await service.resolve(_game(name: 'Portal 2'), allowNetwork: true);
      expect(service.debugCacheSize, 1);

      service.shutdown();
      expect(service.debugCacheSize, 0);

      await service.resolve(_game(name: 'Portal 2'), allowNetwork: true);
      expect(client.requests.length, 2);
      service.shutdown();
    });
  });

  group('SteamAppIdLookup', () {
    test('extracts the steamapps root from an installed game path', () {
      expect(
        SteamAppIdLookup.steamAppsPathFromGamePath(
          r'D:\SteamLibrary\steamapps\common\Portal 2',
        ),
        r'D:\SteamLibrary\steamapps',
      );
    });

    test('returns null for paths outside a steam library', () {
      expect(
        SteamAppIdLookup.steamAppsPathFromGamePath(r'C:\Games\Foo'),
        isNull,
      );
    });

    test('a non-steam path never reaches the bridge', () {
      // No bridge is available in a unit test; a path the wrapper can rule out
      // locally must not attempt the call at all.
      expect(SteamAppIdLookup.resolveAppId(r'C:\Games\Foo', null), isNull);
    });

    test('a null bridge degrades to null rather than throwing', () {
      expect(
        SteamAppIdLookup.resolveAppId(
          r'D:\SteamLibrary\steamapps\common\Portal 2',
          null,
        ),
        isNull,
      );
    });
  });
}
