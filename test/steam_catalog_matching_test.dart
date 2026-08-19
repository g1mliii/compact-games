import 'package:compact_games/services/game_catalog_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Folding and candidate classification, tested against the real store names
/// that were getting these games no cover art and no player count.
void main() {
  group('foldGameTitle', () {
    test('closes an apostrophe up instead of splitting the word', () {
      // The folder on disk says "Rinas Undercover"; Steam says "Rina's
      // Undercover Train Operation". Splitting on the apostrophe folded those
      // to "rina s undercover…" and "rinas undercover", which share no prefix,
      // so the game matched nothing and fell through to a blank exe icon.
      expect(foldGameTitle("Rina's Undercover"), 'rinas undercover');
      expect(foldGameTitle('Rinas Undercover'), 'rinas undercover');
      expect(
        foldGameTitle("Rina's Undercover Train Operation"),
        startsWith(foldGameTitle('Rinas Undercover')),
      );
    });

    test('handles the curly apostrophe stores actually publish', () {
      expect(foldGameTitle('Rina’s Undercover'), 'rinas undercover');
      expect(foldGameTitle("Assassin's Creed"), 'assassins creed');
    });

    test('still folds diacritics and separators', () {
      expect(foldGameTitle('Summer at Smile Café'), 'summer at smile cafe');
      expect(foldGameTitle('Pokémon: Legends – Z-A'), 'pokemon legends z a');
    });
  });

  group('isAncillaryStoreItem', () {
    const succubus = 'succubus successor';

    test('recognizes the add-ons Steam returns beside a game', () {
      for (final name in <String>[
        'succubus successor digital artbook',
        'succubus successor original soundtrack',
        'succubus successor deluxe weapon appearance pack',
        'rinas undercover train operation demo',
      ]) {
        expect(
          isAncillaryStoreItem(
            name,
            name.startsWith(succubus) ? succubus : 'rinas undercover',
          ),
          isTrue,
          reason: name,
        );
      }
    });

    test('does not mistake the game itself for an add-on', () {
      expect(
        isAncillaryStoreItem(
          'succubus successor delilahs juicy journey',
          succubus,
        ),
        isFalse,
      );
      expect(
        isAncillaryStoreItem(
          'rinas undercover train operation',
          'rinas undercover',
        ),
        isFalse,
      );
    });

    test('only judges the text beyond the query', () {
      // A game actually called "Demo Ranch" is not an add-on for itself.
      expect(isAncillaryStoreItem('demo ranch', 'demo ranch'), isFalse);
      expect(isAncillaryStoreItem('pack master', 'pack master'), isFalse);
    });

    test('a candidate that does not start with the query is not judged', () {
      expect(isAncillaryStoreItem('some other soundtrack', succubus), isFalse);
    });
  });

  group('isSubtitledMatch', () {
    test('accepts the query plus a subtitle', () {
      expect(
        isSubtitledMatch(
          'succubus successor delilahs juicy journey',
          'succubus successor',
        ),
        isTrue,
      );
    });

    test('rejects a different title that merely starts the same way', () {
      // The word boundary is what keeps a short name from swallowing a longer
      // unrelated one.
      expect(isSubtitledMatch('portalknights', 'portal'), isFalse);
    });

    test('rejects an identical title, which is an exact match instead', () {
      expect(isSubtitledMatch('starbreed', 'starbreed'), isFalse);
    });

    test('rejects the next game in a series, which appends a single word', () {
      // Steam's own titles: a folder called "Portal" or "Half Life" must not
      // pick these up, since each is a different game with its own app id.
      expect(isSubtitledMatch('portal knights', 'portal'), isFalse);
      expect(isSubtitledMatch('half life alyx', 'half life'), isFalse);
      expect(isSubtitledMatch('fallout shelter', 'fallout'), isFalse);
    });
  });
}
