import 'package:compact_games/core/theme/app_theme.dart';
import 'package:compact_games/features/games/presentation/widgets/library_home/library_home_news_card.dart';
import 'package:compact_games/features/games/presentation/widgets/library_home/library_home_news_shelf.dart';
import 'package:compact_games/features/games/presentation/widgets/library_home/library_home_surface.dart';
import 'package:compact_games/models/game_info.dart';
import 'package:compact_games/models/game_news_item.dart';
import 'package:compact_games/models/news_body.dart';
import 'package:compact_games/providers/games/game_list_provider.dart';
import 'package:compact_games/providers/games/library_home_news_provider.dart';
import 'package:compact_games/providers/games/selected_game_provider.dart';
import 'package:compact_games/providers/system/platform_shell_provider.dart';
import 'package:compact_games/services/platform_shell_service.dart';
import 'package:compact_games/services/steam_news_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/library_home_offline.dart';

const int _oneGiB = 1024 * 1024 * 1024;
const String _gamePath = r'C:\Games\pixel_raider';
final DateTime _now = DateTime.utc(2026, 5, 1, 12);

final List<GameInfo> _games = <GameInfo>[
  GameInfo(
    name: 'Pixel Raider',
    path: _gamePath,
    platform: Platform.steam,
    sizeBytes: 96 * _oneGiB,
    steamAppId: 620,
  ),
];

GameNewsItem _item(int index, {bool withBody = true, String? bodyText}) =>
    GameNewsItem(
      id: 'gid$index',
      gamePath: _gamePath,
      steamAppId: 620,
      title: 'Headline $index',
      url: 'https://store.steampowered.com/news/app/620/view/gid$index',
      publishedAt: DateTime.utc(2026, 4, 30, 12 - index),
      body: withBody
          ? (bodyText ?? 'The full text of announcement $index.')
          : null,
    );

/// A cache that is fresh at [_now], so mounting the shelf paints it and asks
/// for no refresh.
class _FreshStore implements SteamNewsStore {
  _FreshStore(this.items);

  final List<GameNewsItem> items;

  @override
  Future<CachedNewsSnapshot> load() async =>
      CachedNewsSnapshot(items: items, fetchedAt: _now);

  @override
  Future<void> save(List<GameNewsItem> items, {required DateTime now}) async {}
}

/// Records the links the shelf hands to the shell instead of opening them.
class _RecordingShellService implements PlatformShellService {
  final List<String> launched = <String>[];

  @override
  Future<bool> launchUri(String uri) async {
    launched.add(uri);
    return true;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(ProviderContainer, _RecordingShellService)> _pumpSurface(
  WidgetTester tester, {
  required int itemCount,
  bool bodies = true,
  String? bodyText,
  Size size = const Size(900, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final shell = _RecordingShellService();
  final container = ProviderContainer(
    overrides: [
      rustBridgeServiceProvider.overrideWithValue(GamesBridgeService(_games)),
      platformShellServiceProvider.overrideWithValue(shell),
      ...libraryHomeOfflineOverrides(
        newsStore: _FreshStore(<GameNewsItem>[
          for (var i = 0; i < itemCount; i++)
            _item(i, withBody: bodies, bodyText: bodyText),
        ]),
      ),
      newsClockProvider.overrideWithValue(() => _now),
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
  return (container, shell);
}

/// The reader's panel key, which the widget itself keeps private.
const Key _readerKey = ValueKey<String>('libraryHomeNewsReader');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the news shelf is the first thing on the surface', (
    tester,
  ) async {
    await _pumpSurface(tester, itemCount: 3);

    final surface = tester.getTopLeft(
      find.byKey(LibraryHomeSurface.scrollViewKey),
    );
    final shelf = tester.getTopLeft(find.byKey(LibraryHomeNewsShelf.shelfKey));
    expect(shelf.dy - surface.dy, lessThan(8));
  });

  testWidgets('tapping a headline reads it in the app, in place', (
    tester,
  ) async {
    final (container, shell) = await _pumpSurface(tester, itemCount: 3);

    // Tapped on the tile itself: the overlay that carries the gesture sits
    // above the artwork and the headline it draws.
    expect(find.text('Headline 0'), findsOneWidget);
    await tester.tap(find.byType(LibraryHomeNewsCard).first);
    await tester.pumpAndSettle();

    expect(find.text('The full text of announcement 0.'), findsOneWidget);
    // Reading it neither leaves the app nor doubles as a way into the game.
    expect(shell.launched, isEmpty);
    expect(container.read(selectedGameProvider), isNull);
  });

  testWidgets('closing the reader leaves nothing of it behind', (tester) async {
    await _pumpSurface(tester, itemCount: 3);

    await tester.tap(find.byType(LibraryHomeNewsCard).first);
    await tester.pumpAndSettle();
    expect(find.text('The full text of announcement 0.'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // The route and its subtree are gone, so nothing of the article is still
    // mounted once the user is done with it.
    expect(find.text('The full text of announcement 0.'), findsNothing);
    expect(find.text('Close'), findsNothing);
    expect(find.byType(LibraryHomeNewsCard), findsWidgets);
  });

  testWidgets('Escape closes the reader', (tester) async {
    await _pumpSurface(tester, itemCount: 3);

    await tester.tap(find.byType(LibraryHomeNewsCard).first);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('The full text of announcement 0.'), findsNothing);
  });

  testWidgets('the reader still hands the article to a browser on request', (
    tester,
  ) async {
    final (_, shell) = await _pumpSurface(tester, itemCount: 3);

    await tester.tap(find.byType(LibraryHomeNewsCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in browser'));
    await tester.pumpAndSettle();

    expect(shell.launched, <String>[
      'https://store.steampowered.com/news/app/620/view/gid0',
    ]);
  });

  testWidgets('an announcement with no text still opens, and says so', (
    tester,
  ) async {
    await _pumpSurface(tester, itemCount: 1, bodies: false);

    await tester.tap(find.byType(LibraryHomeNewsCard).first);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Steam sent no text for this announcement'),
      findsOneWidget,
    );
  });

  testWidgets('the forward arrow scrolls further headlines into view', (
    tester,
  ) async {
    await _pumpSurface(tester, itemCount: 8);

    expect(find.byKey(LibraryHomeNewsShelf.backArrowKey), findsNothing);
    final forward = find.byKey(LibraryHomeNewsShelf.forwardArrowKey);
    expect(forward, findsOneWidget);

    final before = tester.getTopLeft(find.byType(LibraryHomeNewsCard).first).dx;
    await tester.tap(forward);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byType(LibraryHomeNewsCard).first).dx,
      lessThan(before),
    );
    // Having moved, the shelf now offers the way back.
    expect(find.byKey(LibraryHomeNewsShelf.backArrowKey), findsOneWidget);
  });

  testWidgets('the reader lays the article out as separate paragraphs', (
    tester,
  ) async {
    await _pumpSurface(
      tester,
      itemCount: 1,
      bodyText:
          'Opening paragraph.\n\nChanges:\n- Faster loading\n'
          '- Fewer crashes\n\nClosing paragraph.',
    );

    await tester.tap(find.byType(LibraryHomeNewsCard).first);
    await tester.pumpAndSettle();

    // Each block is its own widget, which is what lets the reader space them
    // apart instead of running them together.
    expect(find.text('Opening paragraph.'), findsOneWidget);
    expect(find.text('Faster loading'), findsOneWidget);
    expect(find.text('Fewer crashes'), findsOneWidget);
    expect(find.text('Closing paragraph.'), findsOneWidget);

    final opening = tester.getBottomLeft(find.text('Opening paragraph.')).dy;
    final changes = tester.getTopLeft(find.text('Changes:')).dy;
    expect(changes - opening, greaterThan(8));
  });

  testWidgets('the reader fills the window it opens over', (tester) async {
    await _pumpSurface(tester, itemCount: 1);

    await tester.tap(find.byType(LibraryHomeNewsCard).first);
    await tester.pumpAndSettle();

    final panel = tester.getSize(find.byKey(_readerKey));
    expect(panel.width, greaterThan(900 * 0.9));
    expect(panel.height, greaterThan(900 * 0.9));
  });

  testWidgets('the reader sets section headings apart from the prose', (
    tester,
  ) async {
    await _pumpSurface(
      tester,
      itemCount: 1,
      bodyText: '${newsBodyHeadingMarker}MAJOR CHANGES\n\nThe first change.',
    );

    await tester.tap(find.byType(LibraryHomeNewsCard).first);
    await tester.pumpAndSettle();

    final heading = tester.widget<Text>(find.text('MAJOR CHANGES'));
    final prose = tester.widget<Text>(find.text('The first change.'));
    expect(
      heading.style!.fontSize,
      greaterThanOrEqualTo(prose.style!.fontSize!),
    );
    expect(
      heading.style!.fontWeight!.value,
      greaterThan(prose.style!.fontWeight!.value),
    );
  });

  testWidgets(
    'dragging the scrollbar scrolls a long announcement',
    (tester) async {
      await _pumpSurface(
        tester,
        itemCount: 1,
        // Long enough that the reader has somewhere to scroll to.
        bodyText: List<String>.generate(
          60,
          (i) => 'Paragraph $i of the announcement.',
        ).join('\n\n'),
      );

      await tester.tap(find.byType(LibraryHomeNewsCard).first);
      await tester.pumpAndSettle();

      // Keyed off the reader: on desktop the Material scroll behavior wraps the
      // view in a scrollbar of its own, so "inside a Scrollbar" matches twice.
      final scrollable = find
          .descendant(
            of: find.byKey(_readerKey),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, 0);

      // A mouse drag on purpose: a scroll view does not follow a mouse drag on
      // the content, so anything that moves here moved because the thumb was
      // grabbed — which is exactly what a scrollbar with no controller cannot do.
      final box = tester.getRect(scrollable);
      final gesture = await tester.startGesture(
        Offset(box.right - 4, box.top + 20),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(() => gesture.removePointer());
      await tester.pump();
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(position.pixels, greaterThan(0));
      // Pinned to Windows because the platform is the whole point: it does not
      // hand out the primary scroll controller, which is what left the bar
      // undraggable. Under the test default (Android) it is handed out and the
      // bug cannot reproduce.
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('a Steam link in the article opens on click', (tester) async {
    const link = 'https://store.steampowered.com/app/2807960/Battlefield_6/';
    final (_, shell) = await _pumpSurface(
      tester,
      itemCount: 1,
      bodyText: 'Grab it at $link today.',
    );

    await tester.tap(find.byType(LibraryHomeNewsCard).first);
    await tester.pumpAndSettle();

    await tester.tapOnText(find.textRange.ofSubstring(link));
    await tester.pumpAndSettle();

    expect(shell.launched, <String>[link]);
  });

  group('readerBodySpans', () {
    const steamLink =
        'https://store.steampowered.com/app/2807960/Battlefield_6/';

    test('picks a bare Steam address out of the prose', () {
      final spans = readerBodySpans('Grab it at $steamLink today.');

      expect(spans.map((s) => s.text).toList(), <String>[
        'Grab it at ',
        steamLink,
        ' today.',
      ]);
      expect(spans[1].url, steamLink);
      expect(spans[0].url, isNull);
      expect(spans[2].url, isNull);
    });

    test('leaves the sentence punctuation outside the link', () {
      final spans = readerBodySpans('See $steamLink.');

      expect(spans.last.text, '.');
      expect(spans.last.url, isNull);
      expect(spans[1].url, steamLink);
    });

    test('does not offer to open somewhere the app would not go', () {
      final spans = readerBodySpans('Read more at https://evil.example.com/x');

      expect(spans.every((s) => s.url == null), isTrue);
      expect(spans.map((s) => s.text).join(), contains('evil.example.com'));
    });

    test('renders a marked link under its own label', () {
      final spans = readerBodySpans(
        'See '
        '$newsBodyLinkStart'
        'the patch notes'
        '$newsBodyLinkSeparator$steamLink$newsBodyLinkEnd'
        ' for details.',
      );

      expect(spans[1].text, 'the patch notes');
      expect(spans[1].url, steamLink);
    });

    test('a block with no link is one plain span', () {
      final spans = readerBodySpans('Nothing to click here.');

      expect(spans.length, 1);
      expect(spans.single.url, isNull);
    });
  });

  group('readerBodyBlocks', () {
    test('marks a heading and strips the marker off its text', () {
      final blocks = readerBodyBlocks(
        '${newsBodyHeadingMarker}MAJOR CHANGES\n\nBody line.',
      );

      expect(blocks.first.text, 'MAJOR CHANGES');
      expect(blocks.first.isHeading, isTrue);
      expect(blocks.last.isHeading, isFalse);
    });

    test('separates paragraphs from list items', () {
      final blocks = readerBodyBlocks(
        'Intro line.\n\n- First item\n- Second item\n\nOutro line.',
      );

      expect(blocks.map((b) => b.text).toList(), <String>[
        'Intro line.',
        'First item',
        'Second item',
        'Outro line.',
      ]);
      expect(blocks.map((b) => b.isBullet).toList(), <bool>[
        false,
        true,
        true,
        false,
      ]);
    });

    test('drops the blank lines that only marked the breaks', () {
      expect(readerBodyBlocks('a\n\n\n\nb').length, 2);
      expect(readerBodyBlocks('   \n  \n'), isEmpty);
    });
  });

  testWidgets('a shelf that fits shows no arrows', (tester) async {
    await _pumpSurface(tester, itemCount: 1);

    expect(find.byKey(LibraryHomeNewsShelf.shelfKey), findsOneWidget);
    expect(find.byKey(LibraryHomeNewsShelf.backArrowKey), findsNothing);
    expect(find.byKey(LibraryHomeNewsShelf.forwardArrowKey), findsNothing);
  });
}
