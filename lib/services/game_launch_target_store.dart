import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/game_path_key.dart';

const _gameLaunchTargetsKey = 'compact_games_launch_targets';

/// Persists user-confirmed executable targets for folder-based games.
class GameLaunchTargetStore {
  const GameLaunchTargetStore();

  Future<String?> read(String gamePath) async {
    final prefs = await SharedPreferences.getInstance();
    final targets = _decodeTargets(prefs.getString(_gameLaunchTargetsKey));
    final target = targets[gamePathKey(gamePath)]?.trim();
    return target == null || target.isEmpty ? null : target;
  }

  Future<void> write(String gamePath, String executablePath) async {
    final prefs = await SharedPreferences.getInstance();
    final targets = _decodeTargets(prefs.getString(_gameLaunchTargetsKey));
    targets[gamePathKey(gamePath)] = executablePath.trim();
    await prefs.setString(_gameLaunchTargetsKey, jsonEncode(targets));
  }

  Future<void> remove(String gamePath) async {
    final prefs = await SharedPreferences.getInstance();
    final targets = _decodeTargets(prefs.getString(_gameLaunchTargetsKey));
    if (targets.remove(gamePathKey(gamePath)) == null) {
      return;
    }
    await prefs.setString(_gameLaunchTargetsKey, jsonEncode(targets));
  }

  Map<String, String> _decodeTargets(String? encoded) {
    if (encoded == null || encoded.isEmpty) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        return <String, String>{};
      }
      return <String, String>{
        for (final entry in decoded.entries)
          if (entry.value is String) entry.key: entry.value as String,
      };
    } catch (_) {
      return <String, String>{};
    }
  }
}
