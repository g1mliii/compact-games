import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../models/game_info.dart';
import '../../../providers/cover_art/cover_art_provider.dart';
import '../../../providers/games/game_list_provider.dart';
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
    final asyncList = ref.watch(gameListProvider);
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
    final watcherActive = ref.watch(
      autoCompressionRunningProvider.select(
        (value) => value.valueOrNull ?? false,
      ),
    );
    final refreshAllowed = !asyncList.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compression Inventory'),
        actions: [
          IconButton(
            tooltip: 'Refresh inventory',
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: refreshAllowed
                ? () => unawaited(_refreshInventoryAndCoverArt())
                : null,
          ),
        ],
      ),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => InventoryError(
          message: 'Failed to load inventory: $error',
          onRetry: () => ref.read(gameListProvider.notifier).refresh(),
        ),
        data: (state) {
          final visibleGames = _computeVisibleGames(state.games);
          final lastCheckedLabel = _formatLastChecked(state.lastRefreshed);

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
                  advancedEnabled: advancedEnabled,
                  onAdvancedChanged: (enabled) => ref
                      .read(settingsProvider.notifier)
                      .setInventoryAdvancedScanEnabled(enabled),
                ),
              ),
              if (advancedEnabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: refreshAllowed
                          ? () => unawaited(_refreshInventoryAndCoverArt())
                          : null,
                      icon: const Icon(LucideIcons.scan),
                      label: const Text('Run Full Inventory Rescan'),
                    ),
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
                              game: game,
                              watcherActive: watcherActive,
                              lastCheckedLabel: lastCheckedLabel,
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
        },
      ),
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

  Future<void> _refreshInventoryAndCoverArt() async {
    await ref.read(gameListProvider.notifier).refresh();

    final games = ref.read(gameListProvider).valueOrNull?.games ?? const [];
    if (games.isEmpty) {
      return;
    }

    final paths = games.map((game) => game.path).toList(growable: false);
    final coverArtService = ref.read(coverArtServiceProvider);
    final placeholders = coverArtService.placeholderRefreshCandidates(paths);
    if (placeholders.isEmpty) {
      return;
    }

    coverArtService.clearLookupCaches();
    coverArtService.invalidateCoverForGames(placeholders);
    for (final path in placeholders) {
      ref.invalidate(coverArtProvider(path));
    }
  }
}
