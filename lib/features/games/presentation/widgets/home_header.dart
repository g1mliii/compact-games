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
  static const double _primaryButtonMinWidth = 176;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final refreshButton = _HeaderActionIconButton(
      icon: LucideIcons.refreshCw,
      tooltip: l10n.homeRefreshGamesTooltip,
      onPressed: () => unawaited(refreshGamesAndInvalidateCovers(ref)),
    );
    const viewToggleButton = _HeaderViewToggleButton();
    final inventoryButton = _HeaderActionIconButton(
      icon: LucideIcons.list,
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
            primaryActionButton: null,
            viewToggleButton: viewToggleButton,
            addGameButton: addGameButton,
            inventoryButton: inventoryButton,
            settingsButton: settingsButton,
            refreshButton: refreshButton,
          ),
        ),
      ),
    );
  }
}

class _HeaderViewToggleButton extends ConsumerWidget {
  const _HeaderViewToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final viewMode = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.homeViewMode ?? HomeViewMode.grid,
      ),
    );

    return _HeaderActionIconButton(
      icon: viewMode == HomeViewMode.grid
          ? LucideIcons.layoutList
          : LucideIcons.layoutGrid,
      tooltip: viewMode == HomeViewMode.grid
          ? l10n.homeSwitchToListViewTooltip
          : l10n.homeSwitchToGridViewTooltip,
      onPressed: () => ref
          .read(settingsProvider.notifier)
          .setHomeViewMode(
            viewMode == HomeViewMode.grid
                ? HomeViewMode.list
                : HomeViewMode.grid,
          ),
    );
  }
}

class _HeaderResponsiveLayout extends StatefulWidget {
  const _HeaderResponsiveLayout({
    required this.breakpoint,
    required this.primaryActionButton,
    required this.viewToggleButton,
    required this.addGameButton,
    required this.inventoryButton,
    required this.settingsButton,
    required this.refreshButton,
  });

  final double breakpoint;
  final Widget? primaryActionButton;
  final Widget viewToggleButton;
  final Widget addGameButton;
  final Widget inventoryButton;
  final Widget settingsButton;
  final Widget refreshButton;

  @override
  State<_HeaderResponsiveLayout> createState() =>
      _HeaderResponsiveLayoutState();
}

class _HeaderResponsiveLayoutState extends State<_HeaderResponsiveLayout> {
  static const double _hidePrimaryActionBreakpoint = 360;
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
        final actions = _utilityActions();
        final showPrimaryAction =
            constraints.maxWidth >= _hidePrimaryActionBreakpoint &&
            widget.primaryActionButton != null;
        final variant = _resolveVariant(
          maxWidth: constraints.maxWidth,
          actionCount: actions.length,
          showPrimaryAction: showPrimaryAction,
        );

        if (_cachedVariant == variant && _cachedChild != null) {
          return _cachedChild!;
        }

        final primary = showPrimaryAction ? widget.primaryActionButton : null;
        final showStatusLine = constraints.maxWidth >= 260;
        final child = switch (variant) {
          _HeaderLayoutVariant.wideWithPrimary => _buildWide(
            actions: actions,
            primary: primary,
            showStatusLine: showStatusLine,
          ),
          _HeaderLayoutVariant.wideUtilityOnly => _buildWide(
            actions: actions,
            primary: null,
            showStatusLine: showStatusLine,
          ),
          _HeaderLayoutVariant.compactInline => _buildCompact(
            actions: actions,
            primary: primary,
            canInline: true,
            showStatusLine: showStatusLine,
          ),
          _HeaderLayoutVariant.compactStacked => _buildCompact(
            actions: actions,
            primary: primary,
            canInline: false,
            showStatusLine: showStatusLine,
          ),
          _HeaderLayoutVariant.compactUtilityOnly => _buildCompact(
            actions: actions,
            primary: null,
            canInline: false,
            showStatusLine: showStatusLine,
          ),
        };
        _cachedVariant = variant;
        _cachedChild = child;
        return child;
      },
    );
  }

  List<Widget> _utilityActions() => <Widget>[
    widget.viewToggleButton,
    widget.addGameButton,
    widget.inventoryButton,
    widget.settingsButton,
    widget.refreshButton,
  ];

  _HeaderLayoutVariant _resolveVariant({
    required double maxWidth,
    required int actionCount,
    required bool showPrimaryAction,
  }) {
    if (maxWidth >= widget.breakpoint) {
      return showPrimaryAction
          ? _HeaderLayoutVariant.wideWithPrimary
          : _HeaderLayoutVariant.wideUtilityOnly;
    }
    if (!showPrimaryAction) {
      return _HeaderLayoutVariant.compactUtilityOnly;
    }

    final actionsWidth =
        (actionCount * appDesktopFrequentActionMin) +
        ((actionCount - 1) * HomeHeader._headerActionSpacing);
    final canInline =
        maxWidth >=
        actionsWidth +
            HomeHeader._primaryButtonMinWidth +
            HomeHeader._headerActionSpacing;
    return canInline
        ? _HeaderLayoutVariant.compactInline
        : _HeaderLayoutVariant.compactStacked;
  }

  Widget _buildCompact({
    required List<Widget> actions,
    required Widget? primary,
    required bool canInline,
    required bool showStatusLine,
  }) {
    return KeyedSubtree(
      key: ValueKey<String>(
        'homeHeaderLayout:${primary == null
            ? 'utility'
            : canInline
            ? 'inline'
            : 'stacked'}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleBlock(showStatusLine: showStatusLine),
          SizedBox(height: primary == null ? 10 : 14),
          const _SearchField(),
          const SizedBox(height: 8),
          if (primary == null)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: HomeHeader._headerActionSpacing,
                runSpacing: HomeHeader._headerActionSpacing,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            )
          else if (canInline)
            Row(
              children: [
                Expanded(child: primary),
                const SizedBox(width: HomeHeader._headerActionSpacing),
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0)
                    const SizedBox(width: HomeHeader._headerActionSpacing),
                  actions[i],
                ],
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                primary,
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: HomeHeader._headerActionSpacing,
                    runSpacing: HomeHeader._headerActionSpacing,
                    alignment: WrapAlignment.end,
                    children: actions,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildWide({
    required List<Widget> actions,
    required Widget? primary,
    required bool showStatusLine,
  }) {
    return KeyedSubtree(
      key: ValueKey<String>(
        'homeHeaderLayout:${primary == null ? 'wide-utility' : 'wide-primary'}',
      ),
      child: Row(
        children: [
          Expanded(child: _TitleBlock(showStatusLine: showStatusLine)),
          const SizedBox(
            width: HomeHeader._wideSearchWidth,
            child: _SearchField(),
          ),
          if (primary != null) ...[
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: HomeHeader._primaryButtonMinWidth,
              ),
              child: primary,
            ),
          ],
          const SizedBox(width: 12),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: HomeHeader._headerActionSpacing),
            actions[i],
          ],
        ],
      ),
    );
  }
}

enum _HeaderLayoutVariant {
  wideWithPrimary,
  wideUtilityOnly,
  compactInline,
  compactStacked,
  compactUtilityOnly,
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
        const Text('PressPlay', style: AppTypography.headingMedium),
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
