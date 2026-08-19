import 'game_news_item.dart';

/// Decodes the announcement body that [boundedNewsBody] produced.
///
/// Lives beside the encoder on purpose: the two agree on a private-use
/// character format that is nobody else's business, and splitting them across
/// layers meant a widget rebuilding the model's markers into a regex of its own.
/// Anything that wants to render, index, or search a body starts here and gets
/// the same links the reader shows.

/// One paragraph, list item, or section heading of an announcement.
typedef ReaderBodyBlock = ({String text, bool isBullet, bool isHeading});

/// A run of one block: plain words, or words that open [url] when clicked.
typedef ReaderBodySpan = ({String text, String? url});

/// Splits a block into its plain and clickable runs.
///
/// Two things become links: a `[url=…]` the sanitizer marked, and a bare
/// address typed into the prose. Both are held to [sanitizedNewsUrl], so a link
/// to somewhere the app would not open stays ordinary text — still readable,
/// still selectable, just not something the reader offers to follow.
List<ReaderBodySpan> readerBodySpans(String text) {
  final spans = <ReaderBodySpan>[];

  void addPlain(String value) {
    if (value.isEmpty) return;
    // A bare address in the middle of a sentence is a link too.
    var index = 0;
    for (final match in _bareUrl.allMatches(value)) {
      final candidate = _trimmedUrl(match[0]!);
      final url = sanitizedNewsUrl(candidate);
      if (url == null) continue;
      if (match.start > index) {
        spans.add((text: value.substring(index, match.start), url: null));
      }
      spans.add((text: candidate, url: url));
      index = match.start + candidate.length;
    }
    if (index < value.length) {
      spans.add((text: value.substring(index), url: null));
    }
  }

  var index = 0;
  for (final match in newsBodyMarkedLink.allMatches(text)) {
    if (match.start > index) {
      addPlain(text.substring(index, match.start));
    }
    final url = sanitizedNewsUrl(match[2]!);
    if (url == null) {
      addPlain(match[1]!);
    } else {
      spans.add((text: match[1]!, url: url));
    }
    index = match.end;
  }
  addPlain(text.substring(index));

  return spans.isEmpty ? <ReaderBodySpan>[(text: text, url: null)] : spans;
}

/// Drops the sentence punctuation that ran into the end of an address.
String _trimmedUrl(String value) {
  var end = value.length;
  while (end > 0 && _urlTrailer.contains(value[end - 1])) {
    end -= 1;
  }
  return value.substring(0, end);
}

const String _urlTrailer = '.,;:!?)]}"\'…';
final RegExp _bareUrl = RegExp(r'https?://\S+');

/// Splits sanitized announcement text into the blocks the reader lays out.
List<ReaderBodyBlock> readerBodyBlocks(String body) {
  final blocks = <ReaderBodyBlock>[];
  for (final line in body.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      // Blank lines are the paragraph separator, not content of their own.
      continue;
    }
    if (trimmed.startsWith(newsBodyHeadingMarker)) {
      final text = trimmed.substring(newsBodyHeadingMarker.length).trim();
      if (text.isEmpty) {
        continue;
      }
      blocks.add((text: text, isBullet: false, isHeading: true));
      continue;
    }
    if (trimmed.startsWith('- ')) {
      blocks.add((
        text: trimmed.substring(2).trim(),
        isBullet: true,
        isHeading: false,
      ));
      continue;
    }
    blocks.add((text: trimmed, isBullet: false, isHeading: false));
  }
  return blocks;
}
