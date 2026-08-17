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

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'gamePath': gamePath,
    'steamAppId': steamAppId,
    'title': title,
    'url': url,
    'publishedAt': publishedAt.toUtc().millisecondsSinceEpoch,
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
        other.publishedAt == publishedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, gamePath, steamAppId, title, url, publishedAt);
}

const int maxNewsIdLength = 64;
const int maxNewsTitleLength = 160;
const int maxNewsGamePathLength = 512;
const int maxNewsUrlLength = 512;

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

final RegExp _htmlTag = RegExp(r'<[^>]*>');
final RegExp _bbCodeTag = RegExp(
  r'\[/?[a-zA-Z0-9*=\s"'
  r"'"
  r':/.\-_]{0,64}\]',
);
final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');
final RegExp _repeatedWhitespace = RegExp(r'\s+');
