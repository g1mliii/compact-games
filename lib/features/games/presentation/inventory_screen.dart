import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/localization/app_localization.dart';
import '../../../core/localization/presentation_labels.dart';
import '../../../models/compression_algorithm.dart';
import '../../../models/game_info.dart';
import '../../../providers/games/game_list_provider.dart';
import '../../../providers/games/refresh_games_helper.dart';
import '../../../providers/settings/settings_provider.dart';
import '../../../providers/system/auto_compression_status_provider.dart';
import 'widgets/inventory_components.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  static const Duration _searchDebounce = Duration(milliseconds: 220);
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  String _debouncedQuery = '';
  InventorySortField _sortField = InventorySortField.savingsPercent;
  bool _descending = true;
  List<GameInfo>? _lastVisibleSource;
  String _lastVisibleQuery = '';
  InventorySortField _lastVisibleSortField = InventorySortField.savingsPercent;
  bool _lastVisibleDescending = true;
  String _lastVisibleExcludedSignature = '';
  List<GameInfo> _cachedVisibleGames = const <GameInfo>[];
  List<String> _cachedVisibleGamePaths = const <String>[];
  List<String>? _cachedListPaths;
  String _cachedListExcludedSignature = '';
  String _cachedListLastCheckedLabel = '';
  bool? _cachedListWatcherActive;
  Widget? _cachedListView;

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final games = ref.watch(
      gameListProvider.select((s) => s.valueOrNull?.games),
    );
    final isLoading = ref.watch(gameListProvider.select((s) => s.isLoading));
    final hasError = ref.watch(gameListProvider.select((s) => s.hasError));
    final errorValue = ref.watch(
      gameListProvider.select((s) => s.hasError ? s.error : null),
    );
    final algorithm = ref.watch(
      settingsProvider.select(
        (value) =>
            value.valueOrNull?.settings.algorithm ??
            CompressionAlgorithm.xpress8k,
      ),
    );
    final algorithmLabel = algorithm.localizedLabel(l10n);
    final advancedEnabled = ref.watch(
      settingsProvider.select(
        (value) =>
            value.valueOrNull?.settings.inventoryAdvancedScanEnabled ?? false,
      ),
    );
    final watcherEnabled = ref.watch(
      settingsProvider.select(
        (value) => value.valueOrNull?.settings.autoCompress ?? false,
      ),
    );
    final excludedPaths = ref.watch(
      settingsProvider.select(
        (value) =>
            value.valueOrNull?.settings.excludedPaths ?? const <String>[],
      ),
    );
    final watcherActive = ref.watch(
      autoCompressionRunningProvider.select(
        (value) => value.valueOrNull ?? false,
      ),
    );
    final lastCheckedLabel = ref.watch(inventoryLastCheckedLabelProvider);
    final refreshAllowed = !isLoading;
    final excludedPathKeys = _normalizedExcludedPathKeys(excludedPaths);
    final excludedSignature = _excludedSignature(excludedPathKeys);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inventoryTitle),
        actions: [
          IconButton(
            tooltip: l10n.inventoryRefreshTooltip,
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: refreshAllowed
                ? () => unawaited(refreshGamesAndInvalidateCovers(ref))
                : null,
          ),
        ],
      ),
      body: () {
        if (games == null && isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (games == null && hasError) {
          return InventoryError(
            message: l10n.inventoryLoadFailed('$errorValue'),
            onRetry: () => ref.read(gameListProvider.notifier).refresh(),
          );
        }
        final gamesList = games ?? const <GameInfo>[];
        final visibleGamePaths = _computeVisibleGamePaths(
          gamesList,
          excludedPathKeys,
        );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: InventoryToolbar(
                searchController: _searchController,
                sortField: _sortField,
                descending: _descending,
                onSearchChanged: _onSearchChanged,
                onSortChanged: (next) => setState(() => _sortField = next),
                onToggleSortDirection: () =>
                    setState(() => _descending = !_descending),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: InventoryStatusRow(
                algorithmLabel: algorithmLabel,
                watcherActive: watcherActive,
                watcherEnabled: watcherEnabled,
                advancedEnabled: advancedEnabled,
                onWatcherEnabledChanged: (enabled) => ref
                    .read(settingsProvider.notifier)
                    .setAutoCompress(enabled),
                onAdvancedChanged: (enabled) => ref
                    .read(settingsProvider.notifier)
                    .setInventoryAdvancedScanEnabled(enabled),
                onRunFullRescan: () =>
                    unawaited(refreshGamesAndInvalidateCovers(ref)),
                canRunFullRescan: refreshAllowed,
              ),
            ),
            const SizedBox(height: 10),
            const InventoryHeader(),
            const SizedBox(height: 4),
            Expanded(
              child: visibleGamePaths.isEmpty
                  ? const InventoryEmpty()
                  : _buildInventoryList(
                      visibleGamePaths,
                      excludedPathKeys: excludedPathKeys,
                      excludedSignature: excludedSignature,
                      watcherActive: watcherActive,
                      lastCheckedLabel: lastCheckedLabel,
                    ),
            ),
          ],
        );
      }(),
    );
  }

  List<GameInfo> _computeVisibleGames(
    List<GameInfo> games,
    Set<String> excludedPathKeys,
  ) {
    final query = _debouncedQuery;
    final excludedSignature = _excludedSignature(excludedPathKeys);
    if (identical(games, _lastVisibleSource) &&
        query == _lastVisibleQuery &&
        _sortField == _lastVisibleSortField &&
        _descending == _lastVisibleDescending &&
        excludedSignature == _lastVisibleExcludedSignature) {
      return _cachedVisibleGames;
    }

    final sorted = <GameInfo>[];
    if (query.isEmpty) {
      sorted.addAll(games);
    } else {
      for (final game in games) {
        if (game.normalizedName.contains(query)) {
          sorted.add(game);
        }
      }
    }
    sorted.sort((a, b) {
      final watchGroupCmp = _watchGroupRank(
        a,
        excludedPathKeys,
      ).compareTo(_watchGroupRank(b, excludedPathKeys));
      if (watchGroupCmp != 0) {
        return watchGroupCmp;
      }

      final cmp = switch (_sortField) {
        InventorySortField.name => a.normalizedName.compareTo(b.normalizedName),
        InventorySortField.originalSize => a.sizeBytes.compareTo(b.sizeBytes),
        InventorySortField.savingsPercent => a.savingsRatio.compareTo(
          b.savingsRatio,
        ),
        InventorySortField.platform => a.platform.name.compareTo(
          b.platform.name,
        ),
      };
      if (cmp != 0) {
        return _descending ? -cmp : cmp;
      }

      final tieBreakCmp = a.normalizedName.compareTo(b.normalizedName);
      if (tieBreakCmp != 0) {
        return tieBreakCmp;
      }

      return a.normalizedPath.compareTo(b.normalizedPath);
    });
    _lastVisibleSource = games;
    _lastVisibleQuery = query;
    _lastVisibleSortField = _sortField;
    _lastVisibleDescending = _descending;
    _lastVisibleExcludedSignature = excludedSignature;
    _cachedVisibleGames = sorted;
    return _cachedVisibleGames;
  }

  List<String> _computeVisibleGamePaths(
    List<GameInfo> games,
    Set<String> excludedPathKeys,
  ) {
    final visibleGames = _computeVisibleGames(games, excludedPathKeys);
    final cachedPaths = _cachedVisibleGamePaths;
    if (cachedPaths.length == visibleGames.length) {
      var matches = true;
      for (var i = 0; i < visibleGames.length; i++) {
        if (cachedPaths[i] != visibleGames[i].path) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return cachedPaths;
      }
    }

    final nextPaths = List<String>.filled(
      visibleGames.length,
      '',
      growable: false,
    );
    for (var i = 0; i < visibleGames.length; i++) {
      nextPaths[i] = visibleGames[i].path;
    }
    _cachedVisibleGamePaths = List<String>.unmodifiable(nextPaths);
    return _cachedVisibleGamePaths;
  }

  Widget _buildInventoryList(
    List<String> visibleGamePaths, {
    required Set<String> excludedPathKeys,
    required String excludedSignature,
    required bool watcherActive,
    required String lastCheckedLabel,
  }) {
    if (identical(_cachedListPaths, visibleGamePaths) &&
        _cachedListExcludedSignature == excludedSignature &&
        _cachedListLastCheckedLabel == lastCheckedLabel &&
        _cachedListWatcherActive == watcherActive &&
        _cachedListView != null) {
      return _cachedListView!;
    }

    final listView = RepaintBoundary(
      key: inventoryListBoundaryKey,
      child: ListView.builder(
        itemExtent: 52,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemCount: visibleGamePaths.length,
        itemBuilder: (context, index) {
          final gamePath = visibleGamePaths[index];
          return InventoryGameRow(
            key: ValueKey(gamePath),
            gamePath: gamePath,
            excludedPathKeys: excludedPathKeys,
            watcherActive: watcherActive,
            lastCheckedLabel: lastCheckedLabel,
            isStriped: index.isOdd,
          );
        },
      ),
    );
    _cachedListPaths = visibleGamePaths;
    _cachedListExcludedSignature = excludedSignature;
    _cachedListLastCheckedLabel = lastCheckedLabel;
    _cachedListWatcherActive = watcherActive;
    _cachedListView = listView;
    return listView;
  }

  Set<String> _normalizedExcludedPathKeys(List<String> paths) {
    final normalized = <String>{};
    for (final path in paths) {
      normalized.add(path.toLowerCase());
    }
    return normalized;
  }

  String _excludedSignature(Set<String> excludedPathKeys) {
    final normalized = excludedPathKeys.toList()..sort();
    return normalized.join('|');
  }

  bool _isWatchedGame(GameInfo game, Set<String> excludedPathKeys) {
    return game.isCompressed && !excludedPathKeys.contains(game.normalizedPath);
  }

  int _watchGroupRank(GameInfo game, Set<String> excludedPathKeys) {
    return _isWatchedGame(game, excludedPathKeys) ? 0 : 1;
  }

  void _onSearchChanged(String value) {
    final normalized = value.trim().toLowerCase();
    _searchDebounceTimer?.cancel();
    if (normalized.isEmpty) {
      if (_debouncedQuery.isEmpty) {
        return;
      }
      setState(() => _debouncedQuery = '');
      return;
    }

    _searchDebounceTimer = Timer(_searchDebounce, () {
      if (!mounted || _debouncedQuery == normalized) {
        return;
      }
      setState(() => _debouncedQuery = normalized);
    });
  }
}
