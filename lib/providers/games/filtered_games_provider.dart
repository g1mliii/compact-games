import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_info.dart';
import 'game_list_provider.dart';
import 'game_list_state.dart';

// Intentionally non-autoDispose: this memo object must live for the full app
// lifecycle to remain effective. Do not convert to autoDispose without also
// clearing memo state in ref.onDispose, or the cache will persist with stale
// references across scope recreations.
final _sortedGamesMemoProvider = Provider<_SortedGamesMemo>((ref) {
  return _SortedGamesMemo();
});

// Intentionally non-autoDispose: this memo object must live for the full app
// lifecycle to remain effective. Do not convert to autoDispose without also
// clearing memo state in ref.onDispose, or the cache will persist with stale
// references across scope recreations.
final _filteredGamePathsMemoProvider = Provider<_FilteredGamePathsMemo>((ref) {
  return _FilteredGamePathsMemo();
});

final _gamesProvider = Provider<List<GameInfo>>((ref) {
  return ref.watch(
        gameListProvider.select((asyncState) => asyncState.valueOrNull?.games),
      ) ??
      const <GameInfo>[];
});

/// Derived provider: applies filters + sort + search to the full game list.
/// Watches only filter/sort inputs to avoid work on unrelated state updates.
final filteredGamesProvider = Provider<List<GameInfo>>((ref) {
  final sortedGamesMemo = ref.watch(_sortedGamesMemoProvider);
  final inputs = ref.watch(
    gameListProvider.select((asyncState) {
      final state = asyncState.valueOrNull;
      if (state == null) {
        return null;
      }
      return (
        games: state.games,
        searchQuery: state.searchQuery,
        platformFilter: state.platformFilter,
        compressionFilter: state.compressionFilter,
        sortField: state.sortField,
        sortDirection: state.sortDirection,
      );
    }),
  );

  if (inputs == null) {
    return const <GameInfo>[];
  }

  return _applyFiltersAndSort(
    sortedGamesMemo: sortedGamesMemo,
    games: inputs.games,
    searchQuery: inputs.searchQuery,
    platformFilter: inputs.platformFilter,
    compressionFilter: inputs.compressionFilter,
    sortField: inputs.sortField,
    sortDirection: inputs.sortDirection,
  );
});

/// Stable visible-path list for list/grid widgets that only care about
/// membership/order, not every metadata field on each game.
final filteredGamePathsProvider = Provider<List<String>>((ref) {
  final pathMemo = ref.watch(_filteredGamePathsMemoProvider);
  final games = ref.watch(filteredGamesProvider);
  return pathMemo.pathsFor(games);
});

final platformCountsProvider = Provider<Map<Platform, int>>((ref) {
  final games = ref.watch(_gamesProvider);
  final counts = <Platform, int>{};
  for (final game in games) {
    counts[game.platform] = (counts[game.platform] ?? 0) + 1;
  }
  return counts;
});

List<GameInfo> _applyFiltersAndSort({
  required _SortedGamesMemo sortedGamesMemo,
  required List<GameInfo> games,
  required String searchQuery,
  required Set<Platform> platformFilter,
  required CompressionFilter compressionFilter,
  required GameSortField sortField,
  required SortDirection sortDirection,
}) {
  final query = searchQuery.isEmpty ? null : searchQuery.toLowerCase();
  final hasPlatformFilter = platformFilter.isNotEmpty;
  final sortedGames = sortedGamesMemo.sort(
    games: games,
    sortField: sortField,
    sortDirection: sortDirection,
  );
  final filtered = <GameInfo>[];

  for (final game in sortedGames) {
    if (query != null && !game.normalizedName.contains(query)) {
      continue;
    }
    if (hasPlatformFilter && !platformFilter.contains(game.platform)) {
      continue;
    }
    if (!_matchesCompressionFilter(game, compressionFilter)) {
      continue;
    }
    filtered.add(game);
  }

  return filtered;
}

bool _matchesCompressionFilter(GameInfo game, CompressionFilter filter) {
  return switch (filter) {
    CompressionFilter.all => true,
    CompressionFilter.compressed => game.isCompressed,
    CompressionFilter.uncompressed =>
      !game.isCompressed && !game.isDirectStorage && !game.isUnsupported,
  };
}

class _SortedGamesMemo {
  List<GameInfo>? _lastGames;
  GameSortField? _lastSortField;
  SortDirection? _lastSortDirection;
  List<GameInfo> _lastSorted = const <GameInfo>[];

  List<GameInfo> sort({
    required List<GameInfo> games,
    required GameSortField sortField,
    required SortDirection sortDirection,
  }) {
    if (identical(_lastGames, games) &&
        _lastSortField == sortField &&
        _lastSortDirection == sortDirection) {
      return _lastSorted;
    }

    final sorted = List<GameInfo>.from(games)
      ..sort((a, b) => _compare(a, b, sortField, sortDirection));
    _lastGames = games;
    _lastSortField = sortField;
    _lastSortDirection = sortDirection;
    _lastSorted = List<GameInfo>.unmodifiable(sorted);
    return _lastSorted;
  }

  int _compare(
    GameInfo a,
    GameInfo b,
    GameSortField sortField,
    SortDirection sortDirection,
  ) {
    final cmp = switch (sortField) {
      GameSortField.name => _compareByName(a, b),
      GameSortField.sizeBytes => a.sizeBytes.compareTo(b.sizeBytes),
      GameSortField.savingsRatio => a.savingsRatio.compareTo(b.savingsRatio),
      GameSortField.platform => a.platform.name.compareTo(b.platform.name),
    };
    return sortDirection == SortDirection.ascending ? cmp : -cmp;
  }

  int _compareByName(GameInfo a, GameInfo b) {
    final normalized = a.normalizedName.compareTo(b.normalizedName);
    if (normalized != 0) {
      return normalized;
    }
    final raw = a.name.compareTo(b.name);
    if (raw != 0) {
      return raw;
    }
    return a.path.compareTo(b.path);
  }
}

class _FilteredGamePathsMemo {
  List<String> _lastPaths = const <String>[];

  List<String> pathsFor(List<GameInfo> games) {
    if (games.isEmpty) {
      _lastPaths = const <String>[];
      return _lastPaths;
    }

    final lastPaths = _lastPaths;
    if (lastPaths.length == games.length) {
      var matches = true;
      for (var i = 0; i < games.length; i++) {
        if (lastPaths[i] != games[i].path) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return lastPaths;
      }
    }

    final nextPaths = List<String>.filled(games.length, '', growable: false);
    for (var i = 0; i < games.length; i++) {
      nextPaths[i] = games[i].path;
    }

    _lastPaths = List<String>.unmodifiable(nextPaths);
    return _lastPaths;
  }
}
