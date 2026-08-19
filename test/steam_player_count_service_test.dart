import 'dart:convert';

import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/models/game_player_count.dart';
import 'package:compact_games/services/steam_player_count_service.dart';
import 'package:flutter_test/flutter_test.dart';

const int _oneGiB = 1024 * 1024 * 1024;

GameInfo _game({
  required String name,
  required String path,
  Platform platform = Platform.steam,
  int sizeBytes = _oneGiB,
  int? steamAppId,
}) {
  return GameInfo(
    name: name,
    path: path,
    platform: platform,
    sizeBytes: sizeBytes,
    steamAppId: steamAppId,
  );
}

GamePlayerCount _count(String path, int players) =>
    GamePlayerCount(gamePath: path, players: players);

void main() {
  group('parsePlayerCount', () {
    test('reads a well-formed reply', () {
      // Captured from api.steampowered.com; the whole body is this short.
      const body = '{"response":{"player_count":814354,"result":1}}';

      expect(parsePlayerCount(jsonDecode(body)), 814354);
    });

    test('refuses a reply that did not succeed', () {
      expect(
        parsePlayerCount(<String, dynamic>{
          'response': <String, dynamic>{'player_count': 5, 'result': 42},
        }),
        isNull,
      );
      expect(
        parsePlayerCount(<String, dynamic>{
          'response': <String, dynamic>{'player_count': 5},
        }),
        isNull,
      );
    });

    test('treats an empty game as no row rather than a zero', () {
      expect(
        parsePlayerCount(<String, dynamic>{
          'response': <String, dynamic>{'player_count': 0, 'result': 1},
        }),
        isNull,
      );
    });

    test('rejects counts outside the plausible range', () {
      for (final value in <int>[-1, maxPlausiblePlayerCount + 1]) {
        expect(
          parsePlayerCount(<String, dynamic>{
            'response': <String, dynamic>{'player_count': value, 'result': 1},
          }),
          isNull,
          reason: '$value',
        );
      }
    });

    test('malformed payload shapes return null rather than throwing', () {
      for (final raw in <String>[
        '{}',
        '{"response": 5}',
        '{"response": {"player_count": "many", "result": 1}}',
        '[]',
        'null',
      ]) {
        expect(parsePlayerCount(jsonDecode(raw)), isNull, reason: raw);
      }
    });
  });

  group('orderPlayerCountCandidates', () {
    test('asks about the largest installs first', () {
      final ordered = orderPlayerCountCandidates(<GameInfo>[
        _game(name: 'Small', path: r'C:\a', sizeBytes: 2 * _oneGiB),
        _game(name: 'Huge', path: r'C:\b', sizeBytes: 90 * _oneGiB),
        _game(name: 'Medium', path: r'C:\c', sizeBytes: 40 * _oneGiB),
      ]);

      expect(ordered.map((g) => g.name), <String>['Huge', 'Medium', 'Small']);
    });

    test('considers games from every platform', () {
      // A game bought outside Steam is usually on Steam too, and its
      // population is the same number. The app id for one with no local
      // manifest is resolved by name later, so nothing is filtered out here.
      final ordered = orderPlayerCountCandidates(<GameInfo>[
        _game(name: 'Steam game', path: r'C:\a', sizeBytes: 3 * _oneGiB),
        _game(
          name: 'Epic game',
          path: r'C:\b',
          platform: Platform.epicGames,
          sizeBytes: 2 * _oneGiB,
        ),
        _game(
          name: 'Repack',
          path: r'C:\c',
          platform: Platform.custom,
          sizeBytes: _oneGiB,
        ),
      ]);

      expect(ordered.map((g) => g.name), <String>[
        'Steam game',
        'Epic game',
        'Repack',
      ]);
    });

    test('caps the number of games asked about', () {
      final ordered = orderPlayerCountCandidates(<GameInfo>[
        for (var i = 0; i < 40; i++)
          _game(
            name: 'G$i',
            path:
                r'C:\g'
                '$i',
            sizeBytes: i * _oneGiB,
          ),
      ]);

      expect(ordered.length, SteamPlayerCountService.maxCandidates);
    });
  });

  group('rankPlayerCounts', () {
    test('busiest first, capped for display', () {
      final ranked = rankPlayerCounts(<GamePlayerCount>[
        for (var i = 0; i < SteamPlayerCountService.maxVisibleItems + 6; i++)
          _count(
            r'C:\g'
            '$i',
            i * 1000,
          ),
      ]);

      expect(ranked.length, SteamPlayerCountService.maxVisibleItems);
      // The busiest survive the cut; the quietest are the ones dropped.
      expect(
        ranked.first.players,
        (SteamPlayerCountService.maxVisibleItems + 5) * 1000,
      );
      expect(ranked.last.players, 6000);
    });

    test('one row per game', () {
      final ranked = rankPlayerCounts(<GamePlayerCount>[
        _count(r'C:\a', 10),
        _count(r'C:\a', 20),
        _count(r'C:\b', 5),
      ]);

      expect(ranked.length, 2);
      expect(ranked.first.gamePath, r'C:\a');
    });

    test('ties break on path so the order does not shuffle', () {
      final ranked = rankPlayerCounts(<GamePlayerCount>[
        _count(r'C:\b', 10),
        _count(r'C:\a', 10),
      ]);

      expect(ranked.map((c) => c.gamePath), <String>[r'C:\a', r'C:\b']);
    });
  });
}
