/// Release-site and scene-group suffixes commonly appended to extracted games.
///
/// Keep this list data-driven so a newly observed tag is a one-line addition.
const List<String> _gameReleaseSuffixes = <String>[
  'SteamGG.NET',
  'SteamRIP',
  'FitGirl Repack',
  'FitGirl',
  'DODI Repack',
  'DODI',
  'ElAmigos',
  'CODEX',
  'PLAZA',
  'SKIDROW',
  'EMPRESS',
  'RUNE',
  'TENOKE',
];
const Set<String> _ambiguousGameReleaseSuffixes = <String>{
  'CODEX',
  'PLAZA',
  'SKIDROW',
  'EMPRESS',
  'RUNE',
  'TENOKE',
};

final RegExp _bracketedGameNameFragment = RegExp(r'\[[^\]]*\]|\([^()]*\)');
final RegExp _junkBracketMarker = RegExp(
  r'(?:\bv(?:ersion)?\s*\d|\bbuild\s*\d|\bearly\s+access\b|\brepack\b|'
  r'\b(?:steamgg(?:\.net)?|steamrip|fitgirl|dodi|elamigos)\b|'
  r'\b(?:codex|plaza|skidrow|empress|rune|tenoke)\b|'
  r'\b(?:multi\d*|language|languages|english|spanish|french|german|'
  r'italian|russian|polish|portuguese|japanese|korean|chinese)\b|\bgog\b)',
  caseSensitive: false,
);
final List<RegExp> _trailingGameNameFragments = <RegExp>[
  RegExp(
    r'(?:\s*[-–—|:_]\s*|\s+)v(?:ersion\s*)?\d+(?:\.\d+){0,4}'
    r'(?:[-._]?[a-z]+\d*)?\s*$',
    caseSensitive: false,
  ),
  RegExp(
    r'(?:\s*[-–—|:_]\s*|\s+)build\s+\d+(?:\.\d+)*\s*$',
    caseSensitive: false,
  ),
  RegExp(r'(?:\s*[-–—|:_]\s*|\s+)early\s+access\s*$', caseSensitive: false),
  RegExp(r'\s*[-–—|:_]\s*gog\s*$', caseSensitive: false),
  RegExp(r'(?:\s*[-–—|:_]\s*|\s+)repack\s*$', caseSensitive: false),
];
final RegExp _trailingSeparators = RegExp(r'[\s\-–—|_:]+$');
final RegExp _leadingSeparators = RegExp(r'^[\s\-–—|_:]+');
final RegExp _separatorRuns = RegExp(r'\s*[|_]+\s*');
final RegExp _whitespaceRuns = RegExp(r'\s+');

/// Returns a lookup/display-friendly game name without common repack noise.
///
/// Meaningful punctuation and parenthesized title text are preserved. Only
/// bracketed fragments containing known version, repack, or language markers
/// are removed.
String normalizeGameName(String gameName) {
  final original = gameName.trim();
  if (original.isEmpty) {
    return original;
  }

  var normalized = original.replaceAllMapped(_bracketedGameNameFragment, (
    match,
  ) {
    final fragment = match.group(0)!;
    final contents = fragment.substring(1, fragment.length - 1);
    return _junkBracketMarker.hasMatch(contents) ? ' ' : fragment;
  });

  var changed = true;
  while (changed) {
    final before = normalized;
    for (final suffix in _gameReleaseSuffixes) {
      final boundary = _ambiguousGameReleaseSuffixes.contains(suffix)
          ? r'\s*[-–—|:_]\s*'
          : r'(?:\s*[-–—|:_]\s*|\s+)';
      normalized = normalized.replaceFirst(
        RegExp(
          '$boundary${RegExp.escape(suffix)}\\s*\$',
          caseSensitive: false,
        ),
        '',
      );
    }
    for (final fragment in _trailingGameNameFragments) {
      normalized = normalized.replaceFirst(fragment, '');
    }
    normalized = normalized.replaceFirst(_trailingSeparators, '');
    changed = normalized != before;
  }

  normalized = normalized
      .replaceAll(_separatorRuns, ' ')
      .replaceAll(_whitespaceRuns, ' ')
      .replaceFirst(_leadingSeparators, '')
      .replaceFirst(_trailingSeparators, '')
      .trim();
  return normalized.isEmpty ? original : normalized;
}
