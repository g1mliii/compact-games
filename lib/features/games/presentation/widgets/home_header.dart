import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/cover_art/cover_art_provider.dart';
import '../../../../providers/games/filtered_games_provider.dart';
import '../../../../providers/games/game_list_provider.dart';

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  static const BorderRadius _panelRadius = BorderRadius.all(
    Radius.circular(16),
  );
  static const double _compactHeaderBreakpoint = 720;
  static const ValueKey<String> _addGamePathFieldKey = ValueKey<String>(
    'addGamePathField',
  );
  static const ValueKey<String> _confirmAddGameButtonKey = ValueKey<String>(
    'confirmAddGameButton',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalSavings = ref.watch(totalSavingsProvider);
    final savedGB = totalSavings.savedBytes / (1024 * 1024 * 1024);
    final savedBadgeWidgets = totalSavings.savedBytes > 0
        ? <Widget>[
            Text(
              '${savedGB.toStringAsFixed(1)} GB saved',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.desertGold,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]
        : const <Widget>[];
    final refreshButton = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: IconButton(
        icon: const Icon(LucideIcons.refreshCw, size: 18),
        color: AppColors.richGold,
        onPressed: () => unawaited(_refreshGamesAndCoverArt(ref)),
        tooltip: 'Refresh games',
      ),
    );
    final inventoryButton = _RouteIconButton(
      icon: LucideIcons.list,
      tooltip: 'Compression inventory',
      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.inventory),
    );
    final addGameButton = _RouteIconButton(
      icon: LucideIcons.folderPlus,
      tooltip: 'Add game',
      onPressed: () => unawaited(_promptAddGame(context, ref)),
    );
    final settingsButton = _RouteIconButton(
      icon: LucideIcons.settings,
      tooltip: 'Settings',
      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
    );

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.panelGradient,
          border: Border.all(color: AppColors.border),
          borderRadius: _panelRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < _compactHeaderBreakpoint;
              final titleBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PressPlay', style: AppTypography.headingMedium),
                  Text(
                    'Cinematic compression control',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: titleBlock),
                        if (savedBadgeWidgets.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          ...savedBadgeWidgets,
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(child: _SearchField()),
                        const SizedBox(width: 8),
                        addGameButton,
                        const SizedBox(width: 8),
                        inventoryButton,
                        const SizedBox(width: 8),
                        settingsButton,
                        const SizedBox(width: 8),
                        refreshButton,
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  titleBlock,
                  const SizedBox(width: 18),
                  ...savedBadgeWidgets,
                  const Spacer(),
                  const SizedBox(width: 240, child: _SearchField()),
                  const SizedBox(width: 8),
                  addGameButton,
                  const SizedBox(width: 8),
                  inventoryButton,
                  const SizedBox(width: 8),
                  settingsButton,
                  const SizedBox(width: 8),
                  refreshButton,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _refreshGamesAndCoverArt(WidgetRef ref) async {
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

  Future<void> _promptAddGame(BuildContext context, WidgetRef ref) async {
    var pendingPath = '';
    String? inputValue;
    inputValue = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Game'),
        content: TextField(
          key: _addGamePathFieldKey,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: r'C:\Games\MyGame or C:\Games\MyGame\game.exe',
          ),
          onChanged: (value) {
            pendingPath = value;
          },
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: _confirmAddGameButtonKey,
            onPressed: () =>
                Navigator.of(dialogContext).pop(pendingPath.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    final value = inputValue?.trim() ?? '';
    if (value.isEmpty) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    await _submitManualGame(context, ref, value);
  }

  Future<void> _submitManualGame(
    BuildContext context,
    WidgetRef ref,
    String pathOrExe,
  ) async {
    try {
      final result = await ref
          .read(gameListProvider.notifier)
          .addGameFromPathOrExe(pathOrExe);
      if (!context.mounted) {
        return;
      }

      final message = result.wasAdded
          ? 'Added "${result.game.name}" to your library.'
          : 'Updated "${result.game.name}" in your library.';
      _showHeaderMessage(context, message);
    } on ArgumentError catch (error) {
      if (!context.mounted) {
        return;
      }
      _showHeaderMessage(context, error.message?.toString() ?? 'Invalid path.');
    } on StateError catch (error) {
      if (!context.mounted) {
        return;
      }
      _showHeaderMessage(context, error.message);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showHeaderMessage(context, 'Failed to add game: $error');
    }
  }

  void _showHeaderMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RouteIconButton extends StatelessWidget {
  const _RouteIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: IconButton(
        icon: Icon(icon, size: 18),
        color: AppColors.richGold,
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  static const Duration _searchDebounce = Duration(milliseconds: 300);
  final _controller = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _controller,
        style: AppTypography.bodySmall,
        decoration: InputDecoration(
          hintText: 'Search games...',
          prefixIcon: const Icon(
            LucideIcons.search,
            size: 16,
            color: AppColors.desertSand,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          fillColor: AppColors.surfaceElevated.withValues(alpha: 0.8),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      ref.read(gameListProvider.notifier).setSearchQuery(value);
    });
  }
}
