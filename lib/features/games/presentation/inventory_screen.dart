import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/navigation/app_routes.dart';
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
  static const String _fallbackAlgorithmLabel = 'XPRESS 8K (Balanced)';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  String _debouncedQuery = '';
  InventorySortField _sortField = InventorySortField.savingsPercent;
  bool _descending = true;
  List<GameInfo>? _lastVisibleSource;
  String _lastVisibleQuery = '';
  InventorySortField _lastVisibleSortField = InventorySortField.savingsPercent;
  bool _lastVisibleDescending = true;
  List<GameInfo> _cachedVisibleGames = const <GameInfo>[];

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final games = ref.watch(
      gameListProvider.select((s) => s.valueOrNull?.games),
    );
    final lastRefreshed = ref.watch(
      gameListProvider.select((s) => s.valueOrNull?.lastRefreshed),
    );
    final isLoading = ref.watch(
      gameListProvider.select((s) => s.isLoading),
    );
    final hasError = ref.watch(
      gameListProvider.select((s) => s.hasError),
    );
    final errorValue = ref.watch(
      gameListProvider.select(
        (s) => s.hasError ? s.error : null,
      ),
    );
    final algorithmLabel = ref.watch(
      settingsProvider.select(
        (value) =>
            value.valueOrNull?.settings.algorithm.displayName ??
            _fallbackAlgorithmLabel,
      ),
    );
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
    final watcherActive = ref.watch(
      autoCompressionRunningProvider.select(
        (value) => value.valueOrNull ?? false,
      ),
    );
    final refreshAllowed = !isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compression Inventory'),
        actions: [
          IconButton(
            tooltip: 'Refresh inventory',
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
            message: 'Failed to load inventory: $errorValue',
            onRetry: () => ref.read(gameListProvider.notifier).refresh(),
          );
        }
        final gamesList = games ?? const <GameInfo>[];
        final visibleGames = _computeVisibleGames(gamesList);
        final lastCheckedLabel = _formatLastChecked(lastRefreshed);

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
                child: visibleGames.isEmpty
                    ? const InventoryEmpty()
                    : RepaintBoundary(
                        child: ListView.builder(
                          itemExtent: 52,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: false,
                          itemCount: visibleGames.length,
                          itemBuilder: (context, index) {
                            final game = visibleGames[index];
                            return InventoryRow(
                              key: ValueKey(game.path),
                              game: game,
                              watcherActive: watcherActive,
                              lastCheckedLabel: lastCheckedLabel,
                              isStriped: index.isOdd,
                              onOpenDetails: () => Navigator.of(
                                context,
                              ).pushNamed(AppRoutes.gameDetails(game.path)),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
      }(),
    );
  }

  List<GameInfo> _computeVisibleGames(List<GameInfo> games) {
    final query = _debouncedQuery;
    if (identical(games, _lastVisibleSource) &&
        query == _lastVisibleQuery &&
        _sortField == _lastVisibleSortField &&
        _descending == _lastVisibleDescending) {
      return _cachedVisibleGames;
    }

    final filtered = query.isEmpty
        ? games
        : games
              .where((g) => g.name.toLowerCase().contains(query))
              .toList(growable: false);
    final sorted = List<GameInfo>.from(filtered);
    sorted.sort((a, b) {
      final cmp = switch (_sortField) {
        InventorySortField.name => a.name.compareTo(b.name),
        InventorySortField.originalSize => a.sizeBytes.compareTo(b.sizeBytes),
        InventorySortField.savingsPercent => a.savingsRatio.compareTo(
          b.savingsRatio,
        ),
        InventorySortField.platform => a.platform.displayName.compareTo(
          b.platform.displayName,
        ),
      };
      return _descending ? -cmp : cmp;
    });
    _lastVisibleSource = games;
    _lastVisibleQuery = query;
    _lastVisibleSortField = _sortField;
    _lastVisibleDescending = _descending;
    _cachedVisibleGames = sorted;
    return _cachedVisibleGames;
  }

  String _formatLastChecked(DateTime? lastChecked) {
    if (lastChecked == null) {
      return 'N/A';
    }
    final hour = lastChecked.hour.toString().padLeft(2, '0');
    final minute = lastChecked.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
