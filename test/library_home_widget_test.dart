import 'package:compact_games/core/theme/app_theme.dart';
import 'package:compact_games/features/games/presentation/widgets/home_game_list_view.dart';
import 'package:compact_games/features/games/presentation/widgets/library_home/library_home_surface.dart';
import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/games/selected_game_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/library_home_offline.dart';
import 'support/list_row_finder.dart';

const int _oneGiB = 1024 * 1024 * 1024;

/// Sorted by name ascending, the list renders Dustline then Pixel Raider.
final List<GameInfo> _games = <GameInfo>[
  GameInfo(
    name: 'Pixel Raider',
    path: r'C:\Games\pixel_raider',
    platform: Platform.steam,
    sizeBytes: 96 * _oneGiB,
    compressedSize: 60 * _oneGiB,
    isCompressed: true,
    lastCompressedAt: DateTime.utc(2026, 5, 1),
  ),
  GameInfo(
    name: 'Dustline',
    path: r'C:\Games\dustline',
    platform: Platform.epicGames,
    sizeBytes: 48 * _oneGiB,
  ),
];

Future<ProviderContainer> _pumpListView(
  WidgetTester tester, {
  List<GameInfo> games = const <GameInfo>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = ProviderContainer(
    overrides: [
      rustBridgeServiceProvider.overrideWithValue(GamesBridgeService(games)),
      // Library Home fetches news and player counts the moment it mounts.
      ...libraryHomeOfflineOverrides(),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: HomeGameListView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('Library Home is the default surface when nothing is selected', (
    tester,
  ) async {
    final container = await _pumpListView(tester, games: _games);

    expect(container.read(selectedGameProvider), isNull);
    expect(listRowText('Library Home'), findsOneWidget);
    expect(find.byKey(LibraryHomeSurface.scrollViewKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Selecting the Library Home row clears the game selection', (
    tester,
  ) async {
    final container = await _pumpListView(tester, games: _games);

    await tester.tap(listRowText('Pixel Raider'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGameProvider), r'C:\Games\pixel_raider');
    expect(find.byKey(LibraryHomeSurface.scrollViewKey), findsNothing);

    await tester.tap(listRowText('Library Home'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGameProvider), isNull);
    expect(find.byKey(LibraryHomeSurface.scrollViewKey), findsOneWidget);
  });

  testWidgets('Keyboard navigation reaches Library Home at the top', (
    tester,
  ) async {
    final container = await _pumpListView(tester, games: _games);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    // Down from Library Home lands on the first game rather than skipping it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(container.read(selectedGameProvider), r'C:\Games\dustline');

    // Up from the first game returns to Library Home, which is the null
    // selection.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(container.read(selectedGameProvider), isNull);

    // Library Home is the top of the list: Up must not wrap around.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(container.read(selectedGameProvider), isNull);
  });

  testWidgets('Up resolves a filtered-out selection to Library Home', (
    tester,
  ) async {
    final container = await _pumpListView(tester, games: _games);

    await tester.tap(listRowText('Pixel Raider'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGameProvider), r'C:\Games\pixel_raider');

    // Filtering the selected game out of the list leaves the selection dangling
    // — the details pane still shows it, but no row does.
    container.read(gameListProvider.notifier).setSearchQuery('dustline');
    await tester.pumpAndSettle();

    // Tapping the row already focused the list, so Up goes straight to it. Both
    // directions have to resolve the dangling selection: Up maps it to index 0,
    // and must act on that rather than treat it as "already there".
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(container.read(selectedGameProvider), isNull);
    expect(find.byKey(LibraryHomeSurface.scrollViewKey), findsOneWidget);
  });

  testWidgets('Library Home stays reachable with an empty library', (
    tester,
  ) async {
    final container = await _pumpListView(tester);

    expect(container.read(selectedGameProvider), isNull);
    expect(find.text('Library Home'), findsOneWidget);
    expect(find.text('Nothing matches this view'), findsOneWidget);
    expect(find.text('No games discovered yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
