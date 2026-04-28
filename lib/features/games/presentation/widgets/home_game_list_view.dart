import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:compact_games/l10n/app_localizations.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/localization/presentation_labels.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/status_badge.dart';
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

  static const double _listPanelWidth = 320;
  static const double _stackedBreakpoint = 560;
  static const double _heightBucket = 20.0;
  static const double _contentTopInset = 8.0;

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
          final bucketed = bucketHomeGameListPanelHeight(constraints.maxHeight);

          if (stacked == _stacked && bucketed == _bucketedHeight) {
            return _buildStacked();
          }
          _stacked = stacked;
          _bucketedHeight = bucketed;
          return _buildStacked();
        }

        if (stacked == _stacked) return _buildSideBySide();
        _stacked = stacked;
        return _buildSideBySide();
      },
    );
  }

  Widget _buildSideBySide() {
    return const Padding(
      padding: EdgeInsets.only(top: HomeGameListView._contentTopInset),
      child: _sideBySide,
    );
  }

  Widget _buildStacked() {
    return Padding(
      padding: const EdgeInsets.only(top: HomeGameListView._contentTopInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _bucketedHeight,
            child: const RepaintBoundary(child: _GameListPanel()),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const Expanded(child: RepaintBoundary(child: _DetailPanel())),
        ],
      ),
    );
  }
}

@visibleForTesting
double bucketHomeGameListPanelHeight(double maxHeight) {
  final raw = maxHeight.isFinite
      ? (maxHeight * 0.34).clamp(90.0, 280.0)
      : 240.0;
  return ((raw / HomeGameListView._heightBucket).floor() *
          HomeGameListView._heightBucket)
      .clamp(90.0, 280.0)
      .toDouble();
}

class _GameListPanel extends ConsumerWidget {
  const _GameListPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamePaths = ref.watch(filteredGamePathsProvider);
    final l10n = context.l10n;

    if (gamePaths.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.searchX,
                size: 22,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                l10n.homeListEmptyTitle,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.homeListEmptyMessage,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: gamePaths.length,
      itemExtent: 72,
      addRepaintBoundaries: true,
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final gamePath = gamePaths[index];
        return _GameListRow(key: ValueKey(gamePath), gamePath: gamePath);
      },
    );
  }
}

class _GameListRow extends ConsumerWidget {
  const _GameListRow({required this.gamePath, super.key});

  final String gamePath;

  static final _selectedDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        AppColors.selectionSurface.withValues(alpha: 0.9),
        AppColors.focusFill.withValues(alpha: 0.14),
      ],
    ),
    border: Border(
      left: BorderSide(color: AppColors.richGold, width: 3),
      top: BorderSide(color: AppColors.selectionBorder),
      bottom: BorderSide(color: AppColors.selectionBorder),
    ),
  );
  static const _defaultDecoration = BoxDecoration(
    border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
  );
  static final _selectedTextStyle = AppTypography.bodySmall.copyWith(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );
  static final _defaultTextStyle = AppTypography.bodySmall.copyWith(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w400,
  );
  static final _platformSelectedStyle = AppTypography.label.copyWith(
    color: AppColors.textPrimary.withValues(alpha: 0.82),
    fontWeight: FontWeight.w600,
  );
  static final _platformDefaultStyle = AppTypography.label.copyWith(
    color: AppColors.textMuted,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
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

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            platformIcon(gameData.platform),
            size: 15,
            color: isSelected ? AppColors.richGold : AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gameData.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isSelected ? _selectedTextStyle : _defaultTextStyle,
                ),
                const SizedBox(height: 3),
                Text(
                  gameData.platform.localizedLabel(l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isSelected
                      ? _platformSelectedStyle
                      : _platformDefaultStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _StatusPill(
                  isCompressed: gameData.isCompressed,
                  isDirectStorage: gameData.isDirectStorage,
                  isUnsupported: gameData.isUnsupported,
                  l10n: l10n,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: isSelected ? _selectedDecoration : _defaultDecoration,
        child: InkWell(
          onTap: () => ref.read(selectedGameProvider.notifier).state = gamePath,
          mouseCursor: SystemMouseCursors.click,
          overlayColor: appInteractionOverlay,
          hoverColor: isSelected ? Colors.transparent : AppColors.hoverSurface,
          focusColor: AppColors.hoverSurface,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          child: content,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.isCompressed,
    required this.isDirectStorage,
    required this.isUnsupported,
    required this.l10n,
  });

  final bool isCompressed;
  final bool isDirectStorage;
  final bool isUnsupported;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData? icon, String label) = switch ((
      isCompressed,
      isDirectStorage,
      isUnsupported,
    )) {
      (_, true, _) => (
        AppColors.directStorage,
        LucideIcons.alertTriangle,
        l10n.gameStatusDirectStorage,
      ),
      (_, _, true) => (
        AppColors.warning,
        LucideIcons.ban,
        l10n.gameStatusUnsupported,
      ),
      (true, _, _) => (
        AppColors.compressed,
        LucideIcons.checkCircle2,
        l10n.gameDetailsStatusCompressed,
      ),
      _ => (AppColors.info, null, l10n.homeStatusReadyToCompress),
    };

    return StatusBadge(
      color: color,
      icon: icon,
      label: label,
      variant: StatusBadgeVariant.outlined,
      toneAlpha: 0.85,
    );
  }
}

class _DetailPanel extends ConsumerWidget {
  const _DetailPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPath = ref.watch(selectedGameProvider);

    if (selectedPath == null) {
      final l10n = context.l10n;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.mousePointerClick,
                size: 36,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.homeSelectGameTitle,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.homeSelectGameMessage,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GameDetailsBody(
      key: ValueKey(selectedPath),
      gamePath: selectedPath,
      // The list on the left already shows a status pill per game, so
      // suppress the cover overlay to avoid showing the same chip twice.
      hideCoverStatusOverlay: true,
    );
  }
}
