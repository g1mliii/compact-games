import 'dart:convert';

import 'package:compact_games/models/game_news_item.dart';
import 'package:compact_games/services/steam_news_store.dart';
import 'package:flutter_test/flutter_test.dart';

GameNewsItem _item({
  required String id,
  DateTime? publishedAt,
  String title = 'A headline',
  String url = 'https://steamcommunity.com/games/1/announcements/detail/1',
  String gamePath = r'C:\Games\game',
}) {
  return GameNewsItem(
    id: id,
    gamePath: gamePath,
    steamAppId: 620,
    title: title,
    url: url,
    publishedAt: publishedAt ?? DateTime.utc(2026, 6, 1),
  );
}

void main() {
  final now = DateTime.utc(2026, 6, 2, 12);

  group('sanitizedNewsUrl', () {
    test('accepts allowlisted https Steam hosts', () {
      expect(
        sanitizedNewsUrl('https://steamcommunity.com/app/620/announcements'),
        isNotNull,
      );
      expect(
        sanitizedNewsUrl('https://store.steampowered.com/news/app/620'),
        isNotNull,
      );
      // A leading dot in the allowlist matches subdomains.
      expect(
        sanitizedNewsUrl('https://partner.steamcommunity.com/news/1'),
        isNotNull,
      );
    });

    test('rejects non-https, foreign hosts, and lookalikes', () {
      expect(sanitizedNewsUrl('http://steamcommunity.com/news'), isNull);
      expect(sanitizedNewsUrl('https://evil.example.com/news'), isNull);
      // A suffix that is not a subdomain boundary must not slip through.
      expect(sanitizedNewsUrl('https://notsteamcommunity.com/news'), isNull);
      expect(sanitizedNewsUrl('javascript:alert(1)'), isNull);
      expect(sanitizedNewsUrl(''), isNull);
      expect(sanitizedNewsUrl(42), isNull);
    });

    test('rejects an over-long url outright', () {
      final long = 'https://steamcommunity.com/${'a' * 600}';
      expect(sanitizedNewsUrl(long), isNull);
    });
  });

  group('boundedNewsText', () {
    test('strips html and bbcode markup', () {
      expect(
        boundedNewsText('<b>Patch</b> notes', maxNewsTitleLength),
        'Patch notes',
      );
      expect(
        boundedNewsText('[h1]Update[/h1] 1.2', maxNewsTitleLength),
        'Update 1.2',
      );
    });

    test('collapses control characters and whitespace', () {
      expect(
        boundedNewsText('Line\u0000one\n\n  two', maxNewsTitleLength),
        'Line one two',
      );
    });

    test('truncates to the cap and rejects markup-only input', () {
      final long = 'x' * 300;
      expect(boundedNewsText(long, maxNewsTitleLength)!.length, 160);
      expect(boundedNewsText('<b></b>', maxNewsTitleLength), isNull);
      expect(boundedNewsText('   ', maxNewsTitleLength), isNull);
      expect(boundedNewsText(null, maxNewsTitleLength), isNull);
    });

    test('rejects a wildly oversized string before cleaning it', () {
      expect(boundedNewsText('y' * 20000, maxNewsTitleLength), isNull);
    });
  });

  group('SteamNewsStore.encode', () {
    test('returns null for an empty list', () {
      expect(SteamNewsStore.encode(const <GameNewsItem>[], now: now), isNull);
    });

    test('caps at 24 items, keeping the newest', () {
      final items = <GameNewsItem>[
        for (var i = 0; i < 40; i++)
          _item(
            id: 'id$i',
            publishedAt: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
          ),
      ];

      final decoded = SteamNewsStore.decode(
        SteamNewsStore.encode(items, now: now),
      );

      expect(decoded.items.length, SteamNewsStore.maxPersistedItems);
      // Newest first, so the last-dated item survives and the oldest does not.
      expect(decoded.items.first.id, 'id39');
      expect(decoded.items.map((i) => i.id), isNot(contains('id0')));
    });

    test('a full payload at the item cap stays inside the byte budget', () {
      final items = <GameNewsItem>[
        for (var i = 0; i < SteamNewsStore.maxPersistedItems; i++)
          _item(
            id: 'id$i',
            title: 'z' * maxNewsTitleLength,
            gamePath: r'C:\Games\' + 'p' * 400,
            url: 'https://steamcommunity.com/${'q' * 400}',
            publishedAt: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
          ),
      ];

      final encoded = SteamNewsStore.encode(items, now: now);
      expect(encoded, isNotNull);
      expect(
        encoded!.length,
        lessThanOrEqualTo(SteamNewsStore.maxPersistedBytes),
      );
      expect(SteamNewsStore.decode(encoded).items.length, 24);
    });

    test('drops oldest items until the byte budget is met', () {
      final items = <GameNewsItem>[
        for (var i = 0; i < 20; i++)
          _item(
            id: 'id$i',
            title: 'z' * maxNewsTitleLength,
            publishedAt: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
          ),
      ];

      // A budget below the natural payload size forces the shrink loop.
      final encoded = SteamNewsStore.encode(items, now: now, maxBytes: 2000);
      expect(encoded, isNotNull);
      expect(encoded!.length, lessThanOrEqualTo(2000));

      final decoded = SteamNewsStore.decode(encoded);
      expect(decoded.items.length, lessThan(20));
      // The newest survives the shrink; the oldest are the ones dropped.
      expect(decoded.items.first.id, 'id19');
      expect(decoded.items.map((i) => i.id), isNot(contains('id0')));
    });

    test('a budget too small for even one item persists nothing', () {
      expect(
        SteamNewsStore.encode(
          <GameNewsItem>[_item(id: 'a')],
          now: now,
          maxBytes: 10,
        ),
        isNull,
      );
    });
  });

  group('SteamNewsStore.decode', () {
    test('an absent or malformed payload decodes to empty', () {
      for (final raw in <String?>[null, '', 'not json', '[]', '{}']) {
        expect(SteamNewsStore.decode(raw).isEmpty, isTrue, reason: '$raw');
      }
      expect(SteamNewsStore.decode('{"items": "nope"}').isEmpty, isTrue);
    });

    test('revalidates cached items and drops the bad ones', () {
      final raw = jsonEncode(<String, dynamic>{
        'fetchedAt': now.millisecondsSinceEpoch,
        'items': <Map<String, dynamic>>[
          _item(id: 'good').toJson(),
          // Cached data is user-writable, so a host swapped after the fact
          // must not survive a reload.
          <String, dynamic>{
            ..._item(id: 'badHost').toJson(),
            'url': 'https://evil.example.com/x',
          },
          <String, dynamic>{
            ..._item(id: 'badDate').toJson(),
            'publishedAt': 10,
          },
          <String, dynamic>{..._item(id: 'badAppId').toJson(), 'steamAppId': 0},
          <String, dynamic>{'nonsense': true},
        ],
      });

      final decoded = SteamNewsStore.decode(raw);
      expect(decoded.items.map((i) => i.id), <String>['good']);
    });

    test('deduplicates repeated ids in a cached payload', () {
      final raw = jsonEncode(<String, dynamic>{
        'fetchedAt': now.millisecondsSinceEpoch,
        'items': <Map<String, dynamic>>[
          _item(id: 'dup').toJson(),
          _item(id: 'dup').toJson(),
        ],
      });

      expect(SteamNewsStore.decode(raw).items.length, 1);
    });

    test('refuses an absurdly large payload without parsing it', () {
      final huge = '{"items":[${'0,' * 200000}0]}';
      expect(SteamNewsStore.decode(huge).isEmpty, isTrue);
    });
  });

  group('CachedNewsSnapshot freshness', () {
    test('is fresh inside the six hour window and stale outside it', () {
      final snapshot = CachedNewsSnapshot(
        items: <GameNewsItem>[_item(id: 'a')],
        fetchedAt: now,
      );

      expect(snapshot.isFreshAt(now.add(const Duration(hours: 5))), isTrue);
      expect(
        snapshot.isFreshAt(now.add(SteamNewsStore.freshness)),
        isTrue,
        reason: 'the boundary itself still counts as fresh',
      );
      expect(
        snapshot.isFreshAt(now.add(const Duration(hours: 6, minutes: 1))),
        isFalse,
      );
    });

    test('a clock that moved backwards is treated as stale, not fresh', () {
      final snapshot = CachedNewsSnapshot(
        items: <GameNewsItem>[_item(id: 'a')],
        fetchedAt: now,
      );
      expect(
        snapshot.isFreshAt(now.subtract(const Duration(days: 1))),
        isFalse,
      );
    });

    test('a snapshot with no timestamp is never fresh', () {
      expect(CachedNewsSnapshot.empty.isFreshAt(now), isFalse);
    });
  });
}
