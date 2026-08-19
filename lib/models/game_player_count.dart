import 'package:flutter/foundation.dart';

/// How many people are in one library game right now.
///
/// Deliberately not persisted: the number is only true for a few minutes, and
/// a "playing now" figure restored from disk at launch would be a lie told
/// confidently. It lives in memory and is refetched.
@immutable
class GamePlayerCount {
  const GamePlayerCount({required this.gamePath, required this.players});

  /// The library game this count belongs to, and the key the row renders from.
  final String gamePath;

  final int players;

  @override
  bool operator ==(Object other) {
    return other is GamePlayerCount &&
        other.gamePath == gamePath &&
        other.players == players;
  }

  @override
  int get hashCode => Object.hash(gamePath, players);
}

/// Ceiling on a reported count.
///
/// Steam's own record is under two million, so anything past this is a
/// malformed or hostile payload rather than a busy game, and a bogus number
/// would otherwise sort itself to the top of the panel forever.
const int maxPlausiblePlayerCount = 50000000;

/// Reads `player_count` from a `GetNumberOfCurrentPlayers` payload.
///
/// Returns null unless the response says it succeeded and carries a count
/// inside [maxPlausiblePlayerCount]; every caller treats that as "no number
/// for this game", which is also what a game nobody is playing looks like
/// after the zero check below.
int? parsePlayerCount(Object? json) {
  if (json is! Map) {
    return null;
  }
  final response = json['response'];
  if (response is! Map) {
    return null;
  }
  // `result` is 1 on success; anything else means the app id has no counter.
  final result = response['result'];
  if (result is! int || result != 1) {
    return null;
  }
  final count = response['player_count'];
  if (count is! int || count < 0 || count > maxPlausiblePlayerCount) {
    return null;
  }
  // Nobody playing is a true answer, but not one worth a row.
  return count == 0 ? null : count;
}
