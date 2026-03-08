import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/platform_icon.dart';
import '../../../../providers/games/filtered_games_provider.dart';
import '../../../../providers/games/selected_game_provider.dart';
import '../../../../providers/games/single_game_provider.dart';
import '../widgets/game_details/game_details_body.dart';

/// Split view: vertical game list on the left, details panel on the right.
///
/// Caches layout mode so continuous window resize only rebuilds the subtree
/// when the stacked/side-by-side breakpoint actually crosses or the bucketed
/// panel height changes.
class HomeGameListView extends StatefulWidget {
  const HomeGameListView({super.key});

  static const double _listPanelWidth = 300;
  static const double _stackedBreakpoint = 560;
  static const double _heightBucket = 20.0;

  @override
  State<HomeGameListView> createState() => _HomeGameListViewState();
}

class _HomeGameListViewState extends State<HomeGameListView> {
  bool? _stacked;
  double _bucketedHeight = 240.0;

  static const Widget _sideBySide = Row(
    children: [
      SizedBox(
        width: HomeGameListView._listPanelWidth,
        child: RepaintBoundary(child: _GameListPanel()),
      ),
      VerticalDivider(width: 1, color: AppColors.borderSubtle),
      Expanded(child: RepaintBoundary(child: _DetailPanel())),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < HomeGameListView._stackedBreakpoint;

        if (stacked) {
          final raw = constraints.maxHeight.isFinite
              ? (constraints.maxHeight * 0.34).clamp(180.0, 280.0)
              : 240.0;
          final bucketed =
              (raw / HomeGameListView._heightBucket).round() *
              HomeGameListView._heightBucket;

          if (stacked == _stacked && bucketed == _bucketedHeight) {
            return _buildStacked();
          }
          _stacked = stacked;
          _bucketedHeight = bucketed;
          return _buildStacked();
        }

        if (stacked == _stacked) return _sideBySide;
        _stacked = stacked;
        return _sideBySide;
      },
    );
  }

  Widget _buildStacked() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _bucketedHeight,
          child: const RepaintBoundary(child: _GameListPanel()),
        ),
        const Divider(height: 1, color: AppColors.borderSubtle),
        const Expanded(child: RepaintBoundary(child: _DetailPanel())),
      ],
    );
  }
}

class _GameListPanel extends ConsumerWidget {
  const _GameListPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(filteredGamesProvider);

    if (games.isEmpty) {
      return const Center(
        child: Text('No games found.', style: AppTypography.bodySmall),
      );
    }

    return ListView.builder(
      itemCount: games.length,
      itemExtent: 48,
      addRepaintBoundaries: true,
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final game = games[index];
        return _GameListRow(key: ValueKey(game.path), gamePath: game.path);
      },
    );
  }
}

class _GameListRow extends ConsumerWidget {
  const _GameListRow({required this.gamePath, super.key});

  final String gamePath;

  static final _selectedColor = AppColors.accent.withValues(alpha: 0.15);
  static final _hoverColor = AppColors.surfaceElevated.withValues(alpha: 0.5);
  static final _selectedTextStyle = AppTypography.bodySmall.copyWith(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );
  static final _defaultTextStyle = AppTypography.bodySmall.copyWith(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w400,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameData = ref.watch(
      singleGameProvider(gamePath).select(
        (g) => g == null
            ? null
            : (
                name: g.name,
                platform: g.platform,
                isCompressed: g.isCompressed,
                isDirectStorage: g.isDirectStorage,
                isUnsupported: g.isUnsupported,
              ),
      ),
    );
    if (gameData == null) return const SizedBox.shrink();

    final isSelected = ref.watch(
      selectedGameProvider.select((selected) => selected == gamePath),
    );

    return Material(
      color: isSelected ? _selectedColor : Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(selectedGameProvider.notifier).state = gamePath,
        hoverColor: _hoverColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                platformIcon(gameData.platform),
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  gameData.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isSelected ? _selectedTextStyle : _defaultTextStyle,
                ),
              ),
              const SizedBox(width: 6),
              _StatusIndicator(
                isCompressed: gameData.isCompressed,
                isDirectStorage: gameData.isDirectStorage,
                isUnsupported: gameData.isUnsupported,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({
    required this.isCompressed,
    required this.isDirectStorage,
    required this.isUnsupported,
  });

  final bool isCompressed;
  final bool isDirectStorage;
  final bool isUnsupported;

  @override
  Widget build(BuildContext context) {
    if (isDirectStorage) {
      return const Icon(
        LucideIcons.alertTriangle,
        size: 12,
        color: AppColors.directStorage,
      );
    }
    if (isUnsupported) {
      return const Icon(LucideIcons.ban, size: 12, color: AppColors.warning);
    }
    if (isCompressed) {
      return const Icon(
        LucideIcons.archive,
        size: 12,
        color: AppColors.compressed,
      );
    }
    return const SizedBox.shrink();
  }
}

class _DetailPanel extends ConsumerWidget {
  const _DetailPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPath = ref.watch(selectedGameProvider);

    if (selectedPath == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.mousePointerClick,
              size: 36,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Select a game to view details',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return GameDetailsBody(key: ValueKey(selectedPath), gamePath: selectedPath);
  }
}
