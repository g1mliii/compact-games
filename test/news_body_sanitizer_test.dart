import 'package:compact_games/models/game_news_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reader renders this text as prose, so the sanitizer has two jobs the
/// headline sanitizer does not: keep paragraph breaks, and leave no asset URL
/// behind where a picture used to be.
void main() {
  group('boundedNewsBody', () {
    test('keeps paragraphs and drops markup', () {
      final body = boundedNewsBody(
        '[h2]Patch 1.2[/h2]Fixed the [b]crash[/b] on load.<br><br>'
        'Also rebalanced the desert map.',
      );

      // The heading keeps a marker the reader styles on; the rest is plain
      // paragraphs.
      expect(
        body,
        '${newsBodyHeadingMarker}Patch 1.2\n\nFixed the crash on load.'
        '\n\nAlso rebalanced the desert map.',
      );
    });

    test('turns bullet markup into a readable list', () {
      final body = boundedNewsBody(
        'Changes:[list][*]Faster loading[*]Fewer crashes[/list]',
      );

      // The list opener contributes the blank line that sets the list off from
      // the sentence introducing it.
      expect(body, 'Changes:\n\n- Faster loading\n- Fewer crashes');
    });

    test('drops embedded images rather than leaving their urls behind', () {
      final body = boundedNewsBody(
        '[img]{STEAM_CLAN_IMAGE}/12345/abcdef.png[/img]The update is live.',
      );

      expect(body, 'The update is live.');
    });

    test('drops a bare asset url that no tag closed', () {
      final body = boundedNewsBody(
        'Look: {STEAM_CLAN_IMAGE}/1/a.png and https://cdn.example.com/b.jpg done',
      );

      expect(body, 'Look: and done');
    });

    test('decodes the entities Steam actually sends', () {
      expect(
        boundedNewsBody('Rock &amp; Roll &mdash; &quot;quoted&quot;'),
        'Rock & Roll — "quoted"',
      );
    });

    test('collapses runaway blank lines', () {
      expect(boundedNewsBody('a</p></p></p></p>b'), 'a\n\nb');
    });

    test('caps the stored length', () {
      final body = boundedNewsBody('word ' * 4000);

      expect(body, isNotNull);
      expect(body!.length, lessThanOrEqualTo(maxNewsBodyLength));
    });

    test('rejects a hostile payload before doing work on it', () {
      expect(boundedNewsBody('x' * (maxNewsBodyLength * 40 + 1)), isNull);
    });

    test('marks a body it had to cut short', () {
      final body = boundedNewsBody('word ' * (maxNewsBodyLength ~/ 2));

      expect(body!.length, lessThanOrEqualTo(maxNewsBodyLength));
      expect(body.endsWith('…'), isTrue);
      // Cut between words, not through one.
      expect(body.endsWith('wor…'), isFalse);
    });

    test('keeps a Steam link under its own label', () {
      const target =
          'https://steamcommunity.com/sharedfiles/filedetails/'
          'changelog/3442040035';
      final body = boundedNewsBody(
        'See the ([url="$target"]Update Notes[/url])'
        ' for details.',
      );

      // Marked rather than flattened, so the reader can offer the target the
      // label stood for.
      expect(
        body,
        'See the ($newsBodyLinkStart'
        'Update Notes'
        '$newsBodyLinkSeparator$target$newsBodyLinkEnd) for details.',
      );
    });

    test('drops the link on a target the app would not open', () {
      final body = boundedNewsBody(
        'See the [url="https://evil.example.com/x"]notes[/url].',
      );

      expect(body, 'See the notes.');
    });

    test('keeps brackets the announcement escaped', () {
      expect(
        boundedNewsBody(r'\[ MAPS \] changed on \[PC]'),
        '[ MAPS ] changed on [PC]',
      );
    });

    test('returns null for anything that is not usable text', () {
      expect(boundedNewsBody(null), isNull);
      expect(boundedNewsBody(42), isNull);
      expect(boundedNewsBody('   '), isNull);
      expect(boundedNewsBody('[img]{STEAM_CLAN_IMAGE}/1/a.png[/img]'), isNull);
    });

    test('survives a round trip through the cache', () {
      final item = GameNewsItem(
        id: 'g1',
        gamePath: r'C:\Games\pixel_raider',
        steamAppId: 620,
        title: 'Headline',
        url: 'https://store.steampowered.com/news/app/620/view/g1',
        publishedAt: DateTime.utc(2026, 5, 1),
        body: 'First paragraph.\n\nSecond paragraph.',
      );

      final restored = GameNewsItem.fromJson(item.toJson());

      expect(restored, item);
      expect(restored!.body, 'First paragraph.\n\nSecond paragraph.');
    });

    test('keeps a marked link and heading across a cache round trip', () {
      const target = 'https://steamcommunity.com/app/620/announcements';
      final body = boundedNewsBody(
        '[h2]Patch 1.2[/h2]See the [url="$target"]notes[/url] for details.',
      );

      final item = GameNewsItem(
        id: 'g1',
        gamePath: r'C:\Games\pixel_raider',
        steamAppId: 620,
        title: 'Headline',
        url: 'https://store.steampowered.com/news/app/620/view/g1',
        publishedAt: DateTime.utc(2026, 5, 1),
        body: body,
      );

      // The markers are what the reader renders links and headings from, so
      // reloading the cache must not quietly strip them back out.
      expect(GameNewsItem.fromJson(item.toJson())!.body, body);
    });

    test('re-bounds a body that was tampered with in the cache file', () {
      final restored = GameNewsItem.fromJson(<String, dynamic>{
        'id': 'g1',
        'gamePath': r'C:\Games\pixel_raider',
        'steamAppId': 620,
        'title': 'Headline',
        'url': 'https://store.steampowered.com/news/app/620/view/g1',
        'publishedAt': DateTime.utc(2026, 5, 1).millisecondsSinceEpoch,
        // A control character, a link opening with no target, and a heading
        // marker stranded mid-sentence: each renders as tofu or worse.
        'body':
            'Fine\u0000 text $newsBodyLinkStart'
            'half a link and a ${newsBodyHeadingMarker}heading',
      });

      expect(restored?.body, 'Fine text half a link and a heading');
    });
  });

  group('restoredNewsBody', () {
    test('leaves a well-formed body exactly as it was stored', () {
      final body = boundedNewsBody(
        '[h2]Notes[/h2]Fixed a [b]crash[/b].[list][*]One[*]Two[/list]',
      );

      expect(restoredNewsBody(body), body);
    });

    test('rejects anything that is not a usable string', () {
      expect(restoredNewsBody(null), isNull);
      expect(restoredNewsBody(42), isNull);
      expect(restoredNewsBody('   '), isNull);
      expect(restoredNewsBody('x' * (maxNewsBodyLength * 40 + 1)), isNull);
    });
  });

  group('_truncatedBody', () {
    test('does not cut a marked link in half', () {
      const target = 'https://steamcommunity.com/app/620/announcements';
      // Padded so the link straddles the cap: what survives the cut must be
      // either a whole link or none of one.
      final body = boundedNewsBody(
        '${'word ' * ((maxNewsBodyLength - 40) ~/ 5)}'
        '[url="$target"]the update notes are over here[/url] and more text',
      );

      expect(body!.length, lessThanOrEqualTo(maxNewsBodyLength));
      expect(
        newsBodyLinkStart.allMatches(body).length,
        newsBodyLinkEnd.allMatches(body).length,
      );
      expect(body.contains(newsBodyLinkStart), isFalse);
    });
  });
}
