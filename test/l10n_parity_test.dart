import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locales shipped alongside the `app_en.arb` template.
const List<String> _translatedLocales = <String>['es', 'zh'];

Map<String, dynamic> _readArb(String locale) {
  final file = File('lib/l10n/app_$locale.arb');
  if (!file.existsSync()) {
    // Thrown at collection time, so it cannot use `expect`.
    throw StateError('missing ${file.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Message keys, excluding the `@key` metadata entries.
Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final template = _readArb('en');
  final templateKeys = _messageKeys(template);

  test('the template defines the Library Home surface strings', () {
    // Guards against a locale file being edited without the template.
    expect(
      templateKeys,
      containsAll(<String>[
        'libraryHomeRowTitle',
        'libraryHomeRowSubtitle',
        'libraryHomeHighlightsHeading',
        'libraryHomeTotalGamesLabel',
        'libraryHomeCompressedLabel',
        'libraryHomeSpaceSavedLabel',
        'libraryHomeLargestInstallLabel',
        'libraryHomeBiggestSaverLabel',
        'libraryHomeRecentlyCompressedLabel',
        'libraryHomeHighlightEmpty',
        'libraryHomeEmptyTitle',
        'libraryHomeEmptyMessage',
        'libraryHomeNewsHeading',
        'libraryHomeNewsSourceSteam',
        'libraryHomeNewsStale',
        'libraryHomeNewsEmpty',
      ]),
    );
  });

  for (final locale in _translatedLocales) {
    group('app_$locale.arb', () {
      final arb = _readArb(locale);
      final localeKeys = _messageKeys(arb);

      test('defines every key the template does', () {
        expect(
          templateKeys.difference(localeKeys),
          isEmpty,
          reason:
              'Untranslated keys fall back to English at runtime, which reads '
              'as a bug rather than a missing translation.',
        );
      });

      test('defines no key the template does not', () {
        expect(
          localeKeys.difference(templateKeys),
          isEmpty,
          reason: 'A key with no template entry is dead weight.',
        );
      });

      test('leaves no message blank', () {
        final blank = <String>[
          for (final key in localeKeys)
            if (arb[key] is! String || (arb[key] as String).trim().isEmpty) key,
        ];
        expect(blank, isEmpty);
      });

      test('agrees with the template on placeholders', () {
        final placeholder = RegExp(r'\{(\w+)\}');
        final mismatched = <String>[];
        for (final key in templateKeys.intersection(localeKeys)) {
          final expected = placeholder
              .allMatches(template[key] as String)
              .map((m) => m.group(1))
              .toSet();
          final actual = placeholder
              .allMatches(arb[key] as String)
              .map((m) => m.group(1))
              .toSet();
          if (expected.length != actual.length ||
              !expected.containsAll(actual)) {
            mismatched.add('$key: expected $expected, found $actual');
          }
        }
        expect(
          mismatched,
          isEmpty,
          reason: 'A dropped placeholder renders a literal brace to the user.',
        );
      });
    });
  }
}
