import 'package:compact_games/core/theme/app_theme.dart';
import 'package:compact_games/features/games/presentation/widgets/library_home/library_home_players_panel.dart';
import 'package:compact_games/features/games/presentation/widgets/library_home/library_home_surface.dart';
import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/models/game_player_count.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/games/library_home_players_provider.dart';
import 'package:compact_games/providers/games/selected_game_provider.dart';
import 'package:compact_games/services/steam_player_count_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/library_home_offline.dart';

const int _oneGiB = 1024 * 1024 * 1024;
final DateTime _now = DateTime.utc(2026, 5, 1, 12);

const String _raiderPath = r'C:\Games\pixel_raider';
const String _dustlinePath = r'C:\Games\dustline';

final List<GameInfo> _games = <GameInfo>[
  GameInfo(
    name: 'Pixel Raider',
    path: _raiderPath,
    platform: Platform.steam,
    sizeBytes: 96 * _oneGiB,
  ),
  GameInfo(
    name: 'Dustline',
    path: _dustlinePath,
    platform: Platform.steam,
    sizeBytes: 48 * _oneGiB,
  ),
];

/// Answers with scripted counts instead of reaching Steam.
class _FakeCountService implements SteamPlayerCountService {
  _FakeCountService({this.result = const <GamePlayerCount>[]});

  List<GamePlayerCount> result;
  int refreshCount = 0;
  int shutdownCount = 0;

  @override
  Future<List<GamePlayerCount>> refresh(
    List<GameInfo> games, {
    Object? rustBridge,
  }) async {
    refreshCount += 1;
    return result;
  }

  @override
  void shutdown() {
    shutdownCount += 1;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(ProviderContainer, _FakeCountService)> _pumpSurface(
  WidgetTester tester, {
  required List<GamePlayerCount> counts,
  DateTime? cachedAt,
  List<GamePlayerCount> cached = const <GamePlayerCount>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final service = _FakeCountService(result: counts);
  final cache = PlayerCountCache();
  if (cachedAt != null) {
    cache.save(cached, now: cachedAt);
  }

  final container = ProviderContainer(
    overrides: [
      rustBridgeServiceProvider.overrideWithValue(GamesBridgeService(_games)),
      ...libraryHomeOfflineOverrides(playerCountService: service),
      playerCountCacheProvider.overrideWithValue(cache),
      playerCountClockProvider.overrideWithValue(() => _now),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: LibraryHomeSurface()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, service);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the panel lists a row per game, busiest first', (tester) async {
    await _pumpSurface(
      tester,
      counts: <GamePlayerCount>[
        const GamePlayerCount(gamePath: _dustlinePath, players: 814354),
        const GamePlayerCount(gamePath: _raiderPath, players: 62490),
      ],
    );

    expect(find.byKey(LibraryHomePlayersPanel.panelKey), findsOneWidget);
    // Grouped for the locale, so a big number stays readable.
    expect(find.text('814,354 playing'), findsOneWidget);
    expect(find.text('62,490 playing'), findsOneWidget);

    // Busiest first, reading down the list.
    final leader = tester.getTopLeft(find.text('814,354 playing')).dy;
    final runnerUp = tester.getTopLeft(find.text('62,490 playing')).dy;
    expect(leader, lessThan(runnerUp));
  });

  testWidgets('tapping a row selects that game', (tester) async {
    final (container, _) = await _pumpSurface(
      tester,
      counts: <GamePlayerCount>[
        const GamePlayerCount(gamePath: _dustlinePath, players: 814354),
      ],
    );

    await tester.tap(find.text('814,354 playing'));
    await tester.pumpAndSettle();

    expect(container.read(selectedGameProvider), _dustlinePath);
  });

  testWidgets('a library nobody is playing shows no panel at all', (
    tester,
  ) async {
    await _pumpSurface(tester, counts: const <GamePlayerCount>[]);

    expect(find.byKey(LibraryHomePlayersPanel.panelKey), findsNothing);
    // The rest of Library Home is unaffected.
    expect(find.byKey(LibraryHomeSurface.scrollViewKey), findsOneWidget);
  });

  testWidgets('a fresh cache paints without asking Steam again', (
    tester,
  ) async {
    final (_, service) = await _pumpSurface(
      tester,
      counts: const <GamePlayerCount>[],
      cachedAt: _now.subtract(const Duration(minutes: 1)),
      cached: <GamePlayerCount>[
        const GamePlayerCount(gamePath: _raiderPath, players: 4321),
      ],
    );

    expect(find.text('4,321 playing'), findsOneWidget);
    expect(service.refreshCount, 0);
  });

  testWidgets('counts past the freshness window are refetched', (tester) async {
    final (_, service) = await _pumpSurface(
      tester,
      counts: <GamePlayerCount>[
        const GamePlayerCount(gamePath: _raiderPath, players: 9999),
      ],
      cachedAt: _now.subtract(const Duration(hours: 2)),
      cached: <GamePlayerCount>[
        const GamePlayerCount(gamePath: _raiderPath, players: 4321),
      ],
    );

    expect(service.refreshCount, 1);
    expect(find.text('9,999 playing'), findsOneWidget);
    expect(find.text('4,321 playing'), findsNothing);
  });

  testWidgets('a failed refresh keeps the last numbers and says so', (
    tester,
  ) async {
    await _pumpSurface(
      tester,
      counts: const <GamePlayerCount>[],
      cachedAt: _now.subtract(const Duration(hours: 2)),
      cached: <GamePlayerCount>[
        const GamePlayerCount(gamePath: _raiderPath, players: 4321),
      ],
    );

    expect(find.text('4,321 playing'), findsOneWidget);
    expect(find.text('Showing last known counts'), findsOneWidget);
  });

  testWidgets('leaving Library Home shuts the request service down', (
    tester,
  ) async {
    final (container, service) = await _pumpSurface(
      tester,
      counts: <GamePlayerCount>[
        const GamePlayerCount(gamePath: _raiderPath, players: 4321),
      ],
    );

    expect(find.byKey(LibraryHomePlayersPanel.panelKey), findsOneWidget);

    // Navigating away unmounts the surface, and the panel's provider is
    // auto-disposing, so nothing else has to remember to stop the requests.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(LibraryHomePlayersPanel.panelKey), findsNothing);
    expect(service.shutdownCount, greaterThan(0));
  });
}
