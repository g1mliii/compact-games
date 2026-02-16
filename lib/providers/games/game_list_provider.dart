import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_info.dart';
import '../../services/rust_bridge_service.dart';
import 'game_list_state.dart';

final rustBridgeServiceProvider = Provider<RustBridgeService>((ref) {
  return RustBridgeService.instance;
});

final gameListProvider = AsyncNotifierProvider<GameListNotifier, GameListState>(
  GameListNotifier.new,
);

class GameListNotifier extends AsyncNotifier<GameListState> {
  static const int _maxConcurrentHydrations = 2;
  static const Duration _hydrationFlushInterval = Duration(milliseconds: 120);

  int _requestGeneration = 0;
  bool _disposed = false;

  final Queue<String> _hydrationQueue = Queue<String>();
  final Set<String> _queuedHydrations = <String>{};
  final Set<String> _inFlightHydrations = <String>{};
  final Set<String> _fullyHydratedPaths = <String>{};
  final Map<String, DateTime> _nextHydrationRetryAt = <String, DateTime>{};
  final Map<String, int> _hydrationFailureCount = <String, int>{};
  final Map<String, GameInfo> _pendingHydratedUpdates = <String, GameInfo>{};

  int _activeHydrations = 0;
  Timer? _hydrationFlushTimer;

  @override
  Future<GameListState> build() async {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _requestGeneration++;
      _hydrationQueue.clear();
      _queuedHydrations.clear();
      _inFlightHydrations.clear();
      _fullyHydratedPaths.clear();
      _nextHydrationRetryAt.clear();
      _hydrationFailureCount.clear();
      _pendingHydratedUpdates.clear();
      _activeHydrations = 0;
      _hydrationFlushTimer?.cancel();
      _hydrationFlushTimer = null;
    });

    final requestId = ++_requestGeneration;
    return _loadGames(requestId, mode: _DiscoveryLoadMode.quick);
  }

  Future<GameListState> _loadGames(
    int requestId, {
    required _DiscoveryLoadMode mode,
  }) async {
    if (_isStaleRequest(requestId)) {
      return state.valueOrNull ?? const GameListState();
    }

    try {
      final bridge = ref.read(rustBridgeServiceProvider);
      final games = switch (mode) {
        _DiscoveryLoadMode.quick => await bridge.getAllGamesQuick(),
        _DiscoveryLoadMode.full => await bridge.getAllGames(),
      };
      if (_isStaleRequest(requestId)) {
        return state.valueOrNull ?? const GameListState();
      }

      _queueResetForNewGameSet(
        games,
        markAsFullyHydrated: mode == _DiscoveryLoadMode.full,
      );
      return _buildLoadedState(games: games);
    } catch (e) {
      if (_isStaleRequest(requestId)) {
        return state.valueOrNull ?? const GameListState();
      }
      return _buildLoadedState(
        games: state.valueOrNull?.games ?? const [],
        error: 'Failed to load games: $e',
      );
    }
  }

  void _queueResetForNewGameSet(
    List<GameInfo> games, {
    required bool markAsFullyHydrated,
  }) {
    final nextPaths = games.map((g) => g.path).toSet();
    _hydrationQueue.removeWhere((path) => !nextPaths.contains(path));
    _queuedHydrations.removeWhere((path) => !nextPaths.contains(path));
    _inFlightHydrations.removeWhere((path) => !nextPaths.contains(path));
    _nextHydrationRetryAt.removeWhere((path, _) => !nextPaths.contains(path));
    _hydrationFailureCount.removeWhere((path, _) => !nextPaths.contains(path));
    _pendingHydratedUpdates.removeWhere((path, _) => !nextPaths.contains(path));

    if (markAsFullyHydrated) {
      _fullyHydratedPaths
        ..clear()
        ..addAll(nextPaths);
    } else {
      _fullyHydratedPaths.clear();
    }
  }

  GameListState _buildLoadedState({
    required List<GameInfo> games,
    String? error,
  }) {
    final previous = state.valueOrNull;
    return GameListState(
      games: games,
      searchQuery: previous?.searchQuery ?? '',
      platformFilter: previous?.platformFilter ?? const {},
      compressionFilter: previous?.compressionFilter ?? CompressionFilter.all,
      sortField: previous?.sortField ?? GameSortField.name,
      sortDirection: previous?.sortDirection ?? SortDirection.ascending,
      lastRefreshed: DateTime.now(),
      error: error,
    );
  }

  /// Full reload from Rust backend.
  /// Uses copyWithPrevious to keep the current data visible during reload.
  Future<void> refresh() async {
    final requestId = ++_requestGeneration;
    state = const AsyncValue<GameListState>.loading().copyWithPrevious(state);
    final next = await _loadGames(requestId, mode: _DiscoveryLoadMode.full);
    if (_isStaleRequest(requestId)) {
      return;
    }
    state = AsyncValue.data(next);
  }

  /// Queue lazy full-metadata hydration for a specific game path.
  /// Safe to call repeatedly from UI build paths.
  void requestHydration(String gamePath) {
    if (_disposed) return;
    if (_fullyHydratedPaths.contains(gamePath)) return;
    if (_queuedHydrations.contains(gamePath)) return;
    if (_inFlightHydrations.contains(gamePath)) return;
    final retryAt = _nextHydrationRetryAt[gamePath];
    if (retryAt != null && DateTime.now().isBefore(retryAt)) {
      return;
    }

    final current = state.valueOrNull;
    if (current == null || current.games.every((g) => g.path != gamePath)) {
      return;
    }

    _hydrationQueue.addLast(gamePath);
    _queuedHydrations.add(gamePath);
    _pumpHydrationQueue();
  }

  void _pumpHydrationQueue() {
    if (_disposed) return;
    while (_activeHydrations < _maxConcurrentHydrations &&
        _hydrationQueue.isNotEmpty) {
      final path = _hydrationQueue.removeFirst();
      _queuedHydrations.remove(path);
      _inFlightHydrations.add(path);
      _activeHydrations += 1;
      unawaited(_hydrateSinglePath(path));
    }
  }

  Future<void> _hydrateSinglePath(String gamePath) async {
    try {
      if (_disposed) return;

      final snapshot = state.valueOrNull;
      final games = snapshot?.games;
      if (games == null) return;
      final matchIndex = games.indexWhere((g) => g.path == gamePath);
      final game = matchIndex >= 0 ? games[matchIndex] : null;
      if (game == null) return;

      final bridge = ref.read(rustBridgeServiceProvider);
      final hydrated = await bridge.hydrateGame(
        gamePath: game.path,
        gameName: game.name,
        platform: game.platform,
      );
      if (_disposed) return;
      if (hydrated == null) {
        _fullyHydratedPaths.add(gamePath);
        _nextHydrationRetryAt.remove(gamePath);
        _hydrationFailureCount.remove(gamePath);
        return;
      }
      _fullyHydratedPaths.add(gamePath);
      _nextHydrationRetryAt.remove(gamePath);
      _hydrationFailureCount.remove(gamePath);
      _queueHydratedUpdate(hydrated);
    } catch (_) {
      // Hydration is best-effort; use bounded exponential backoff for retries.
      final failures = (_hydrationFailureCount[gamePath] ?? 0) + 1;
      _hydrationFailureCount[gamePath] = failures;
      final cappedFailures = failures > 4 ? 4 : failures;
      final backoffSeconds = 1 << cappedFailures;
      _nextHydrationRetryAt[gamePath] = DateTime.now().add(
        Duration(seconds: backoffSeconds),
      );
    } finally {
      _inFlightHydrations.remove(gamePath);
      if (_activeHydrations > 0) {
        _activeHydrations -= 1;
      }
      _pumpHydrationQueue();
    }
  }

  void _queueHydratedUpdate(GameInfo updatedGame) {
    _pendingHydratedUpdates[updatedGame.path] = updatedGame;
    if (_hydrationFlushTimer != null) {
      return;
    }

    _hydrationFlushTimer = Timer(_hydrationFlushInterval, () {
      _hydrationFlushTimer = null;
      if (_disposed || _pendingHydratedUpdates.isEmpty) {
        return;
      }

      final updates = Map<String, GameInfo>.from(_pendingHydratedUpdates);
      _pendingHydratedUpdates.clear();
      _updateState((s) => _applyBatchGameUpdates(s, updates));
    });
  }

  /// Update filter/sort without refetching.
  void setSearchQuery(String query) {
    _updateState((s) => s.copyWith(searchQuery: query));
  }

  void setPlatformFilter(Set<Platform> platforms) {
    _updateState((s) => s.copyWith(platformFilter: platforms));
  }

  void setCompressionFilter(CompressionFilter filter) {
    _updateState((s) => s.copyWith(compressionFilter: filter));
  }

  void setSortField(GameSortField field) {
    _updateState((s) => s.copyWith(sortField: field));
  }

  void toggleSortDirection() {
    _updateState(
      (s) => s.copyWith(
        sortDirection: s.sortDirection == SortDirection.ascending
            ? SortDirection.descending
            : SortDirection.ascending,
      ),
    );
  }

  /// Targeted single-game update for immediate UI feedback.
  void updateGame(GameInfo updatedGame) {
    _updateState((s) => _applySingleGameUpdate(s, updatedGame));
  }

  void _updateState(GameListState Function(GameListState) updater) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = updater(current);
    if (identical(next, current)) return;
    state = AsyncValue.data(next);
  }

  GameListState _applySingleGameUpdate(
    GameListState snapshot,
    GameInfo updatedGame,
  ) {
    final index = snapshot.games.indexWhere((g) => g.path == updatedGame.path);
    if (index < 0) {
      return snapshot;
    }

    final existing = snapshot.games[index];
    if (existing == updatedGame) {
      return snapshot;
    }

    final updatedList = List<GameInfo>.from(snapshot.games);
    updatedList[index] = updatedGame;
    return snapshot.copyWith(games: updatedList);
  }

  GameListState _applyBatchGameUpdates(
    GameListState snapshot,
    Map<String, GameInfo> updates,
  ) {
    var changed = false;
    final updatedList = List<GameInfo>.from(snapshot.games);

    for (var i = 0; i < updatedList.length; i++) {
      final existing = updatedList[i];
      final next = updates[existing.path];
      if (next == null || next == existing) {
        continue;
      }

      updatedList[i] = next;
      changed = true;
    }

    if (!changed) {
      return snapshot;
    }

    return snapshot.copyWith(games: updatedList);
  }

  bool _isStaleRequest(int requestId) =>
      _disposed || requestId != _requestGeneration;
}

enum _DiscoveryLoadMode { quick, full }
