import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_info.dart';
import 'game_list_provider.dart';
import 'game_list_state.dart';

final _sortedGamesMemo = _SortedGamesMemo();

final _gamesProvider = Provider<List<GameInfo>>((ref) {
  return ref.watch(
        gameListProvider.select((asyncState) => asyncState.valueOrNull?.games),
      ) ??
      const <GameInfo>[];
});

/// Derived provider: applies filters + sort + search to the full game list.
/// Watches only filter/sort inputs to avoid work on unrelated state updates.
final filteredGamesProvider = Provider<List<GameInfo>>((ref) {
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
    games: inputs.games,
    searchQuery: inputs.searchQuery,
    platformFilter: inputs.platformFilter,
    compressionFilter: inputs.compressionFilter,
    sortField: inputs.sortField,
    sortDirection: inputs.sortDirection,
  );
});

final platformCountsProvider = Provider<Map<Platform, int>>((ref) {
  final games = ref.watch(_gamesProvider);
  final counts = <Platform, int>{};
  for (final game in games) {
    counts[game.platform] = (counts[game.platform] ?? 0) + 1;
  }
  return counts;
});

final totalSavingsProvider = Provider<({int totalBytes, int savedBytes})>((
  ref,
) {
  final games = ref.watch(_gamesProvider);
  var totalBytes = 0;
  var savedBytes = 0;
  for (final game in games) {
    totalBytes += game.sizeBytes;
    savedBytes += game.bytesSaved;
  }
  return (totalBytes: totalBytes, savedBytes: savedBytes);
});

List<GameInfo> _applyFiltersAndSort({
  required List<GameInfo> games,
  required String searchQuery,
  required Set<Platform> platformFilter,
  required CompressionFilter compressionFilter,
  required GameSortField sortField,
  required SortDirection sortDirection,
}) {
  final query = searchQuery.isEmpty ? null : searchQuery.toLowerCase();
  final hasPlatformFilter = platformFilter.isNotEmpty;
  final sortedGames = _sortedGamesMemo.sort(
    games: games,
    sortField: sortField,
    sortDirection: sortDirection,
  );
  final filtered = <GameInfo>[];

  for (final game in sortedGames) {
    if (query != null && !game.name.toLowerCase().contains(query)) {
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
      !game.isCompressed && !game.isDirectStorage,
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
      GameSortField.name => a.name.compareTo(b.name),
      GameSortField.sizeBytes => a.sizeBytes.compareTo(b.sizeBytes),
      GameSortField.savingsRatio => a.savingsRatio.compareTo(b.savingsRatio),
      GameSortField.platform => a.platform.displayName.compareTo(
        b.platform.displayName,
      ),
    };
    return sortDirection == SortDirection.ascending ? cmp : -cmp;
  }
}
