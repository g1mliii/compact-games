import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../models/app_settings.dart';
import '../../../../providers/games/game_list_provider.dart';
import '../../../../providers/games/refresh_games_helper.dart';
import '../../../../providers/settings/settings_provider.dart';
import 'home_actions.dart';

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  static const BorderRadius _panelRadius = BorderRadius.all(
    Radius.circular(20),
  );
  static const double _compactHeaderBreakpoint = 860;
  static const double _wideSearchWidth = 240;
  static const double _headerActionSpacing = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final refreshButton = _HeaderActionIconButton(
      icon: LucideIcons.refreshCw,
      tooltip: l10n.homeRefreshGamesTooltip,
      onPressed: () => unawaited(refreshGamesAndInvalidateCovers(ref)),
    );
    const viewToggleGroup = _HeaderViewToggleGroup();
    final inventoryButton = _HeaderActionIconButton(
      icon: LucideIcons.archive,
      tooltip: l10n.homeCompressionInventoryTooltip,
      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.inventory),
    );
    final addGameButton = _HeaderActionIconButton(
      icon: LucideIcons.folderPlus,
      tooltip: l10n.homeAddGameTooltip,
      onPressed: () => unawaited(promptAddGame(context, ref)),
    );
    final settingsButton = _HeaderActionIconButton(
      icon: LucideIcons.settings,
      tooltip: l10n.homeSettingsTooltip,
      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
    );

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.82),
          border: Border.all(color: AppColors.borderSubtle),
          borderRadius: _panelRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: _HeaderResponsiveLayout(
            breakpoint: _compactHeaderBreakpoint,
            viewToggleGroup: viewToggleGroup,
            utilityActions: <Widget>[
              addGameButton,
              inventoryButton,
              settingsButton,
              refreshButton,
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderViewToggleGroup extends ConsumerWidget {
  const _HeaderViewToggleGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final viewMode = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.homeViewMode ?? HomeViewMode.grid,
      ),
    );

    void setMode(HomeViewMode mode) {
      ref.read(settingsProvider.notifier).setHomeViewMode(mode);
    }

    return DecoratedBox(
      key: const ValueKey<String>('homeHeaderViewModeGroup'),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withValues(alpha: 0.76),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeaderViewModeButton(
              key: const ValueKey<String>('homeHeaderViewModeList'),
              icon: LucideIcons.layoutList,
              selected: viewMode == HomeViewMode.list,
              tooltip: viewMode == HomeViewMode.list
                  ? null
                  : l10n.homeSwitchToListViewTooltip,
              onPressed: viewMode == HomeViewMode.list
                  ? null
                  : () => setMode(HomeViewMode.list),
            ),
            const SizedBox(width: 4),
            _HeaderViewModeButton(
              key: const ValueKey<String>('homeHeaderViewModeGrid'),
              icon: LucideIcons.layoutGrid,
              selected: viewMode == HomeViewMode.grid,
              tooltip: viewMode == HomeViewMode.grid
                  ? null
                  : l10n.homeSwitchToGridViewTooltip,
              onPressed: viewMode == HomeViewMode.grid
                  ? null
                  : () => setMode(HomeViewMode.grid),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderViewModeButton extends StatelessWidget {
  const _HeaderViewModeButton({
    super.key,
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool selected;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? AppColors.richGold.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.all(
          color: selected
              ? AppColors.richGold.withValues(alpha: 0.28)
              : Colors.transparent,
        ),
      ),
      child: IconButton(
        constraints: const BoxConstraints.tightFor(
          width: appDesktopFrequentActionMin - 6,
          height: appDesktopFrequentActionMin - 6,
        ),
        padding: const EdgeInsets.all(10),
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        color: selected ? AppColors.richGold : AppColors.textSecondary,
      ),
    );

    if (tooltip == null) {
      return child;
    }
    return Tooltip(message: tooltip, child: child);
  }
}

class _HeaderResponsiveLayout extends StatefulWidget {
  const _HeaderResponsiveLayout({
    required this.breakpoint,
    required this.viewToggleGroup,
    required this.utilityActions,
  });

  final double breakpoint;
  final Widget viewToggleGroup;
  final List<Widget> utilityActions;

  @override
  State<_HeaderResponsiveLayout> createState() =>
      _HeaderResponsiveLayoutState();
}

enum _HeaderLayoutVariant { wideGrouped, compactGrouped }

class _HeaderResponsiveLayoutState extends State<_HeaderResponsiveLayout> {
  _HeaderLayoutVariant? _cachedVariant;
  Widget? _cachedChild;

  @override
  void didUpdateWidget(covariant _HeaderResponsiveLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cachedVariant = null;
    _cachedChild = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final variant = constraints.maxWidth >= widget.breakpoint
            ? _HeaderLayoutVariant.wideGrouped
            : _HeaderLayoutVariant.compactGrouped;
        if (_cachedVariant == variant && _cachedChild != null) {
          return _cachedChild!;
        }

        final child = switch (variant) {
          _HeaderLayoutVariant.wideGrouped => _buildWide(showStatusLine: true),
          _HeaderLayoutVariant.compactGrouped => _buildCompact(
            showStatusLine: constraints.maxWidth >= 360,
          ),
        };
        _cachedVariant = variant;
        _cachedChild = child;
        return child;
      },
    );
  }

  Widget _buildCompact({required bool showStatusLine}) {
    return KeyedSubtree(
      key: const ValueKey<String>('homeHeaderLayout:compact-grouped'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleBlock(showStatusLine: showStatusLine),
          const SizedBox(height: 14),
          const _SearchField(),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 12,
              runSpacing: HomeHeader._headerActionSpacing,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [widget.viewToggleGroup, ...widget.utilityActions],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWide({required bool showStatusLine}) {
    return KeyedSubtree(
      key: const ValueKey<String>('homeHeaderLayout:wide-grouped'),
      child: Row(
        children: [
          Expanded(child: _TitleBlock(showStatusLine: showStatusLine)),
          const SizedBox(
            width: HomeHeader._wideSearchWidth,
            child: _SearchField(),
          ),
          const SizedBox(width: 14),
          widget.viewToggleGroup,
          const SizedBox(width: 14),
          for (var i = 0; i < widget.utilityActions.length; i++) ...[
            if (i > 0) const SizedBox(width: HomeHeader._headerActionSpacing),
            widget.utilityActions[i],
          ],
        ],
      ),
    );
  }
}

class _HeaderActionIconButton extends StatelessWidget {
  const _HeaderActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  static const _borderRadius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withValues(alpha: 0.72),
        borderRadius: _borderRadius,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: IconButton(
        constraints: const BoxConstraints.tightFor(
          width: appDesktopFrequentActionMin,
          height: appDesktopFrequentActionMin,
        ),
        padding: const EdgeInsets.all(12),
        icon: Icon(icon, size: 18),
        color: AppColors.textSecondary,
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
    final l10n = context.l10n;
    return SizedBox(
      height: appDesktopFrequentActionMin,
      child: TextField(
        controller: _controller,
        style: AppTypography.bodySmall,
        decoration: InputDecoration(
          hintText: l10n.homeSearchGamesHint,
          hintStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary.withValues(alpha: 0.9),
          ),
          prefixIcon: const Icon(
            LucideIcons.search,
            size: 16,
            color: AppColors.info,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          fillColor: AppColors.surfaceCard.withValues(alpha: 0.84),
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

class _TitleBlock extends ConsumerWidget {
  const _TitleBlock({this.showStatusLine = true});

  final bool showStatusLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Compact Games', style: AppTypography.headingMedium),
        if (showStatusLine) ...[
          const SizedBox(height: 2),
          Text(
            l10n.homeHeaderTagline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
