import 'package:flutter/foundation.dart';

/// One sanitized Steam Community news entry, bounded by construction.
///
/// Every field is trimmed and length-capped at parse time and the URL is
/// validated against an https allowlist, so nothing downstream has to re-check
/// remote strings before painting them.
@immutable
class GameNewsItem {
  const GameNewsItem({
    required this.id,
    required this.gamePath,
    required this.steamAppId,
    required this.title,
    required this.url,
    required this.publishedAt,
    this.body,
  });

  /// Steam's stable `gid`. Used for deduplication across refreshes.
  final String id;

  /// The library game this item was fetched for. Also the cover art key, so no
  /// separate news thumbnail is ever downloaded.
  final String gamePath;

  final int steamAppId;
  final String title;
  final String url;
  final DateTime publishedAt;

  /// The announcement text, stripped to plain paragraphs, or null when Steam
  /// sent none. Optional because a cache written before the reader existed is
  /// still worth showing — such an item opens the reader with its link only.
  final String? body;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'gamePath': gamePath,
    'steamAppId': steamAppId,
    'title': title,
    'url': url,
    'publishedAt': publishedAt.toUtc().millisecondsSinceEpoch,
    if (body != null) 'body': body,
  };

  /// Rebuilds an item from persisted JSON, re-applying every bound.
  ///
  /// Cached data is treated as untrusted: the file is user-writable and a
  /// previous app version may have persisted looser values.
  static GameNewsItem? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = boundedNewsText(json['id'], maxNewsIdLength);
    final gamePath = boundedNewsGamePath(json['gamePath']);
    final title = boundedNewsText(json['title'], maxNewsTitleLength);
    final url = sanitizedNewsUrl(json['url']);
    final appId = json['steamAppId'];
    final millis = json['publishedAt'];

    if (id == null ||
        gamePath == null ||
        title == null ||
        url == null ||
        appId is! int ||
        appId <= 0 ||
        millis is! int) {
      return null;
    }

    final publishedAt = boundedNewsTimestampFromMilliseconds(millis);
    if (publishedAt == null) {
      return null;
    }

    return GameNewsItem(
      id: id,
      gamePath: gamePath,
      steamAppId: appId,
      title: title,
      url: url,
      publishedAt: publishedAt,
      // Re-bounded rather than re-sanitized: the markup strip ran once, at
      // the fetch, and running it again here would eat the markers this body
      // was stored with. See [restoredNewsBody].
      body: restoredNewsBody(json['body']),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GameNewsItem &&
        other.id == id &&
        other.gamePath == gamePath &&
        other.steamAppId == steamAppId &&
        other.title == title &&
        other.url == url &&
        other.publishedAt == publishedAt &&
        other.body == body;
  }

  @override
  int get hashCode =>
      Object.hash(id, gamePath, steamAppId, title, url, publishedAt, body);
}

const int maxNewsIdLength = 64;
const int maxNewsTitleLength = 160;
const int maxNewsGamePathLength = 512;
const int maxNewsUrlLength = 512;

/// Cap on the stored announcement text. Long enough that most patch-notes
/// posts arrive whole, short enough that a full cache stays inside the store's
/// byte budget. A post past the cap is cut at a word boundary and marked; the
/// reader still offers the whole thing on Steam.
const int maxNewsBodyLength = 6000;

/// Hosts a news link may point at. A leading dot matches any subdomain.
const Set<String> trustedNewsHosts = <String>{
  'steamcommunity.com',
  '.steamcommunity.com',
  'store.steampowered.com',
};

/// Trims, strips markup, and caps [value] to [maxLength].
///
/// Returns null for anything that is not a non-empty string once cleaned, so
/// callers can drop the whole item rather than render a blank card.
String? boundedNewsText(Object? value, int maxLength) {
  if (value is! String) {
    return null;
  }
  // Reject before doing work proportional to a hostile payload's size.
  if (value.length > maxLength * 8) {
    return null;
  }

  final stripped = value
      .replaceAll(_htmlTag, ' ')
      .replaceAll(_bbCodeTag, ' ')
      .replaceAll(_controlChars, ' ')
      .replaceAll(_repeatedWhitespace, ' ')
      .trim();
  if (stripped.isEmpty) {
    return null;
  }
  return stripped.length <= maxLength
      ? stripped
      : stripped.substring(0, maxLength).trimRight();
}

/// Trims an announcement body down to plain paragraphs.
///
/// Same distrust as [boundedNewsText] — the source is remote markup — but the
/// reader shows this as a block of prose, so paragraph breaks survive where
/// [boundedNewsText] would flatten them. Embedded images, videos, and their
/// URLs are dropped outright rather than left behind as bare links.
String? boundedNewsBody(Object? value) {
  if (value is! String) {
    return null;
  }
  // Backstop only: the fetch already caps the whole response, so this rejects
  // a cache file someone pasted a novel into rather than a real announcement.
  if (value.length > maxNewsBodyLength * 40) {
    return null;
  }

  final text = value
      // Nothing may arrive already carrying the markers below.
      .replaceAll(_bodyMarkers, '')
      // Announcements escape brackets they mean literally, as in `\[PC]` or
      // `\[ MAPS \]`. Parked out of the way first, or the tag stripper eats
      // them and leaves the stray backslash behind.
      .replaceAll(r'\[', _escapedOpenBracket)
      .replaceAll(r'\]', _escapedCloseBracket)
      .replaceAll(_embeddedMedia, ' ')
      // Before the tag stripper, which would otherwise leave the label with no
      // way back to what it linked to.
      .replaceAllMapped(_anchoredLink, _markedLink)
      .replaceAll(_headingOpen, '\n\n$newsBodyHeadingMarker')
      .replaceAll(_paragraphBreak, '\n\n')
      .replaceAll(_lineBreak, '\n')
      .replaceAll(_listItem, '\n- ')
      .replaceAll(_htmlTag, ' ')
      // Deliberately looser than [boundedNewsText]'s: a `[url="…"]` tag runs
      // well past that one's 64-character allowance, and every bracket the
      // author meant literally is already parked above.
      .replaceAll(_bbCodeTagLoose, ' ')
      .replaceAll(_bareMediaUrl, ' ')
      .replaceAllMapped(
        _htmlEntity,
        (m) => _htmlEntities[m[0]!.toLowerCase()] ?? ' ',
      )
      .replaceAll(_controlCharsExceptNewline, ' ')
      .replaceAll(_horizontalWhitespace, ' ')
      .replaceAll(_spaceAroundNewline, '\n')
      .replaceAll(_manyNewlines, '\n\n')
      .replaceAll(_escapedOpenBracket, '[')
      .replaceAll(_escapedCloseBracket, ']')
      .trim();

  if (text.isEmpty) {
    return null;
  }
  return text.length <= maxNewsBodyLength ? text : _truncatedBody(text);
}

/// Re-bounds an announcement body read back from the cache.
///
/// Deliberately not [boundedNewsBody]: that one's first act is to strip the
/// private-use markers, because nothing arriving from Steam may carry them —
/// and a persisted body is written *in* those markers, so re-running it turned
/// every stored link back into a label glued to its target and flattened every
/// heading into ordinary prose. Stripping markup belongs at the trust
/// boundary, once, and has to stay there for a second reason: `&lt;` decodes
/// to a literal `<`, so a second strip would keep eating text on every reload
/// instead of settling on one answer.
///
/// What is still checked is everything a hand-edited cache file can do to the
/// reader: length, control characters, and markers that lost their other half.
String? restoredNewsBody(Object? value) {
  if (value is! String) {
    return null;
  }
  // Same backstop as [boundedNewsBody]: a cache file someone pasted a novel
  // into is rejected before any work is done proportional to its size.
  if (value.length > maxNewsBodyLength * 40) {
    return null;
  }

  final text = _withoutStrayMarkers(
    value
        .replaceAll(_controlCharsExceptNewline, ' ')
        .replaceAll(_horizontalWhitespace, ' ')
        .replaceAll(_spaceAroundNewline, '\n')
        .replaceAll(_manyNewlines, '\n\n')
        .trim(),
  );

  if (text.isEmpty) {
    return null;
  }
  return text.length <= maxNewsBodyLength ? text : _truncatedBody(text);
}

/// Drops every marker that means nothing where it sits.
///
/// A link marker outside a well-formed link has lost the half that said where
/// it pointed, and a heading marker only means anything at the start of a
/// line; either one renders as private-use tofu if left alone. The escape pair
/// never survives encoding at all, so it is never legitimate here.
String _withoutStrayMarkers(String text) {
  if (!_bodyMarkers.hasMatch(text)) {
    return text;
  }

  final links = newsBodyMarkedLink.allMatches(text).toList();
  final out = StringBuffer();
  var nextLink = 0;
  var atLineStart = true;
  for (var i = 0; i < text.length; i++) {
    if (nextLink < links.length && links[nextLink].start == i) {
      final link = links[nextLink++];
      out.write(link[0]);
      i = link.end - 1;
      atLineStart = false;
      continue;
    }
    final char = text[i];
    if (char == newsBodyHeadingMarker) {
      if (atLineStart) {
        out.write(char);
        atLineStart = false;
      }
      continue;
    }
    final unit = text.codeUnitAt(i);
    if (unit >= 0xE000 && unit <= 0xE005) {
      continue;
    }
    out.write(char);
    atLineStart = char == '\n';
  }
  return out.toString();
}

/// Rewrites one `[url=…]label[/url]` into the reader's link form.
///
/// A target the app would not open — anything off the Steam hosts in
/// [trustedNewsHosts] — keeps its words and loses its link, which is the same
/// line the item's own URL is held to: the reader does not vouch for wherever
/// an announcement points.
String _markedLink(Match match) {
  // Groups 1 and 2 are the BBCode form, 3 and 4 the HTML one.
  final label = (match[2] ?? match[4] ?? '').trim();
  final url = sanitizedNewsUrl((match[1] ?? match[3] ?? '').trim());
  if (url == null) {
    return label;
  }
  if (label.isEmpty) {
    return url;
  }
  return '$newsBodyLinkStart$label$newsBodyLinkSeparator$url$newsBodyLinkEnd';
}

/// Cuts an over-long body back to a word boundary and marks the cut.
///
/// The reader offers the full post on Steam, so what matters here is that the
/// last line reads as a sentence that stops, not as a word sliced in half.
String _truncatedBody(String text) {
  // One char short of the cap, so the ellipsis still fits inside it.
  final hard = text.substring(0, maxNewsBodyLength - 1);
  final breakAt = hard.lastIndexOf(_wordBoundary);
  var kept = breakAt > hard.length - 400 ? hard.substring(0, breakAt) : hard;
  // A cut through a marked link leaves an opening with nothing to close it,
  // which the reader cannot render as a link and would paint as private-use
  // tofu wrapped around a bare address, so the whole opening goes. A heading
  // marker needs no such care: the worst a cut leaves is a heading whose only
  // word is the ellipsis.
  final openedAt = kept.lastIndexOf(newsBodyLinkStart);
  if (openedAt > kept.lastIndexOf(newsBodyLinkEnd)) {
    kept = kept.substring(0, openedAt);
  }
  return '${kept.trimRight()}…';
}

/// Bounds a local install path without stripping markup.
///
/// A game path is locally sourced, not remote text, and it keys the cover art
/// and game lookups the news card renders from. Folders like
/// `Fallout 4 [GOTY]` or names with doubled spaces are legitimate and must
/// survive verbatim, so only control characters and length are rejected — an
/// over-long path is dropped rather than truncated, since a truncated path is a
/// key that matches nothing.
String? boundedNewsGamePath(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > maxNewsGamePathLength) {
    return null;
  }
  return _controlChars.hasMatch(trimmed) ? null : trimmed;
}

/// Steam's own hosted page for a news entry.
///
/// `GetNewsForApp` almost never reports a link on an allowlisted host: even
/// plain Community Announcements arrive as a `steamstore-a.akamaihd.net`
/// redirector, and the rest point at third-party outlets. Rejecting those is
/// right — the shelf must not vouch for `Gamemag.ru` — but rejecting them
/// leaves no link at all, and a link is a required field, so every item was
/// being dropped and the shelf rendered empty.
///
/// The store's news viewer is the stable Steam-hosted page for the same
/// `gid`, on a host already in [trustedNewsHosts], so it is what the item
/// carries. Returns null for a `gid` that is not a bare id, since anything
/// else has no business being interpolated into a URL.
String? steamNewsPermalink(int steamAppId, String gid) {
  if (steamAppId <= 0 || !_newsGid.hasMatch(gid)) {
    return null;
  }
  return 'https://store.steampowered.com/news/app/$steamAppId/view/$gid';
}

/// Validates a news link: https only, an allowlisted host, and length-bounded.
String? sanitizedNewsUrl(Object? value) {
  if (value is! String || value.isEmpty || value.length > maxNewsUrlLength) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme.toLowerCase() != 'https') {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty) {
    return null;
  }
  final allowed = trustedNewsHosts.any(
    (candidate) => candidate.startsWith('.')
        ? host.endsWith(candidate)
        : host == candidate,
  );
  return allowed ? uri.toString() : null;
}

/// Rejects millisecond timestamps far outside the plausible range so a bogus
/// value cannot pin an item to the top of the shelf forever.
DateTime? boundedNewsTimestampFromMilliseconds(int millisSinceEpoch) {
  const earliest = 946684800000; // 2000-01-01
  const latest = 4102444800000; // 2100-01-01
  if (millisSinceEpoch < earliest || millisSinceEpoch > latest) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(millisSinceEpoch, isUtc: true);
}

/// Converts Steam's seconds-since-epoch value after validating it before the
/// multiplication. This avoids both out-of-range [DateTime] construction and
/// integer overflow for malformed remote input.
DateTime? boundedNewsTimestampFromSeconds(int secondsSinceEpoch) {
  // Bounds checked before the multiplication, so the product cannot overflow
  // and is by construction inside the millisecond range — no second check.
  const earliest = 946684800; // 2000-01-01
  const latest = 4102444800; // 2100-01-01
  if (secondsSinceEpoch < earliest || secondsSinceEpoch > latest) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(
    secondsSinceEpoch * 1000,
    isUtc: true,
  );
}

final RegExp _newsGid = RegExp(r'^[0-9a-fA-F]{1,32}$');
final RegExp _htmlTag = RegExp(r'<[^>]*>');
final RegExp _bbCodeTag = RegExp(
  r'\[/?[a-zA-Z0-9*=\s"'
  r"'"
  r':/.\-_]{0,64}\]',
);
final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');
final RegExp _repeatedWhitespace = RegExp(r'\s+');

/// Everything below serves [boundedNewsBody], which keeps the paragraph breaks
/// the shelf's one-line sanitizer throws away.
final RegExp _controlCharsExceptNewline = RegExp(r'[\x00-\x09\x0B-\x1F\x7F]');

/// Pictures and videos, tag and payload together: what sits between the tags
/// is an asset URL, which is noise once the picture itself cannot be shown.
final RegExp _embeddedMedia = RegExp(
  r'\[img\b[^\]]{0,600}\][\s\S]{0,600}?\[/img\]'
  r'|\[previewyoutube\b[^\]]{0,300}\][\s\S]{0,300}?\[/previewyoutube\]'
  r'|\[video\b[^\]]{0,600}\][\s\S]{0,600}?\[/video\]'
  r'|<img\b[^>]{0,600}>',
  caseSensitive: false,
);
final RegExp _paragraphBreak = RegExp(
  r'</p>|\[/p\]|</h[1-6]>|\[/h[1-6]\]',
  caseSensitive: false,
);
final RegExp _lineBreak = RegExp(
  r'<br\s*/?>|\[/?list\]|</li>|\[/\*\]|\[/tr\]|</tr>',
  caseSensitive: false,
);

/// Private-use characters, so a bracket the announcement escaped survives tag
/// stripping and comes back as itself.
const String _escapedOpenBracket = '\u{E000}';
const String _escapedCloseBracket = '\u{E001}';

/// Marks a line that was a heading in the markup, which is the one piece of
/// structure worth carrying past the strip: the reader sets those lines apart
/// instead of dropping a patch note's sections into the surrounding prose.
/// Kept as a private-use character so it cannot collide with article text —
/// the pass below strips any that arrived from Steam.
const String newsBodyHeadingMarker = '\u{E002}';

/// Brackets a link the reader may offer: start, label, separator, target, end.
/// Same private-use trick as the heading marker, for the same reason — the
/// target has to survive tag stripping to be worth keeping at all.
const String newsBodyLinkStart = '\u{E003}';
const String newsBodyLinkSeparator = '\u{E004}';
const String newsBodyLinkEnd = '\u{E005}';

final RegExp _bodyMarkers = RegExp('[\u{E000}-\u{E005}]');

/// One link [_markedLink] wrote: label in group 1, target in group 2. Shared
/// with the decoder in `news_body.dart` so the encoder, the reader, and the
/// cache repair above cannot drift on what a well-formed link looks like.
final RegExp newsBodyMarkedLink = RegExp(
  '$newsBodyLinkStart([^$newsBodyLinkSeparator$newsBodyLinkEnd]*)'
  '$newsBodyLinkSeparator([^$newsBodyLinkStart$newsBodyLinkEnd]*)'
  '$newsBodyLinkEnd',
);
final RegExp _anchoredLink = RegExp(
  r'\[url\s*=\s*"?([^\]"]{1,400})"?\]([\s\S]{0,300}?)\[/url\]'
  r'|<a\b[^>]{0,400}?href\s*=\s*"([^"]{1,400})"[^>]{0,200}?>([\s\S]{0,300}?)</a>',
  caseSensitive: false,
);
final RegExp _headingOpen = RegExp(
  r'\[h[1-6]\b[^\]]{0,80}\]|<h[1-6]\b[^>]{0,80}>',
  caseSensitive: false,
);
final RegExp _bbCodeTagLoose = RegExp(r'\[/?[^\[\]]{0,400}\]');

/// Where [_truncatedBody] prefers to cut: end of a paragraph, or a space.
final RegExp _wordBoundary = RegExp(r'[\s]');
final RegExp _listItem = RegExp(r'<li>|\[\*\]', caseSensitive: false);

/// A leftover asset link on its own, from markup that named no closing tag.
final RegExp _bareMediaUrl = RegExp(
  r'\{STEAM_CLAN[A-Z_]*\}\S*'
  r'|https?://\S+\.(?:png|jpe?g|gif|webp|mp4|webm)\b',
  caseSensitive: false,
);
final RegExp _htmlEntity = RegExp(
  r'&(?:[a-zA-Z]{2,8}|#[0-9]{1,6}|#x[0-9a-fA-F]{1,5});',
);
final RegExp _horizontalWhitespace = RegExp(r'[^\S\n]+');
final RegExp _spaceAroundNewline = RegExp(r' ?\n ?');
final RegExp _manyNewlines = RegExp(r'\n{3,}');

/// The handful of entities Steam's announcements actually carry. Anything else
/// becomes a space, which is the safe reading of an entity nothing decodes.
const Map<String, String> _htmlEntities = <String, String>{
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&#39;': "'",
  '&#34;': '"',
  '&nbsp;': ' ',
  '&mdash;': '—',
  '&ndash;': '–',
  '&hellip;': '…',
  '&rsquo;': '’',
  '&lsquo;': '‘',
  '&rdquo;': '”',
  '&ldquo;': '“',
};
