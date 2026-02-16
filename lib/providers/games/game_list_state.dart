import '../../models/game_info.dart';

/// How games are sorted in the grid.
enum GameSortField {
  name,
  sizeBytes,
  savingsRatio,
  platform;

  String get displayName => switch (this) {
        name => 'Name',
        sizeBytes => 'Size',
        savingsRatio => 'Savings',
        platform => 'Platform',
      };
}

enum SortDirection { ascending, descending }

/// Filter for compression status.
enum CompressionFilter {
  all,
  compressed,
  uncompressed;

  String get displayName => switch (this) {
        all => 'All',
        compressed => 'Compressed',
        uncompressed => 'Uncompressed',
      };
}

/// Immutable state for the game list.
class GameListState {
  final List<GameInfo> games;
  final String searchQuery;
  final Set<Platform> platformFilter;
  final CompressionFilter compressionFilter;
  final GameSortField sortField;
  final SortDirection sortDirection;
  final DateTime? lastRefreshed;
  final String? error;

  const GameListState({
    this.games = const [],
    this.searchQuery = '',
    this.platformFilter = const {},
    this.compressionFilter = CompressionFilter.all,
    this.sortField = GameSortField.name,
    this.sortDirection = SortDirection.ascending,
    this.lastRefreshed,
    this.error,
  });

  int get totalSizeBytes {
    var total = 0;
    for (final game in games) {
      total += game.sizeBytes;
    }
    return total;
  }

  int get totalSavedBytes {
    var total = 0;
    for (final game in games) {
      total += game.bytesSaved;
    }
    return total;
  }

  bool get hasActiveFilters =>
      searchQuery.isNotEmpty ||
      platformFilter.isNotEmpty ||
      compressionFilter != CompressionFilter.all;

  GameListState copyWith({
    List<GameInfo>? games,
    String? searchQuery,
    Set<Platform>? platformFilter,
    CompressionFilter? compressionFilter,
    GameSortField? sortField,
    SortDirection? sortDirection,
    DateTime? Function()? lastRefreshed,
    String? Function()? error,
  }) {
    return GameListState(
      games: games ?? this.games,
      searchQuery: searchQuery ?? this.searchQuery,
      platformFilter: platformFilter ?? this.platformFilter,
      compressionFilter: compressionFilter ?? this.compressionFilter,
      sortField: sortField ?? this.sortField,
      sortDirection: sortDirection ?? this.sortDirection,
      lastRefreshed:
          lastRefreshed != null ? lastRefreshed() : this.lastRefreshed,
      error: error != null ? error() : this.error,
    );
  }
}
