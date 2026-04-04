import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pressplay/l10n/app_localizations.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_formatting.dart';
import '../../../../models/app_settings.dart';
import '../../../../providers/compression/compression_progress_provider.dart';
import '../../../../providers/games/game_list_provider.dart';
import '../../../../providers/games/home_overview_provider.dart';
import '../../../../providers/localization/locale_provider.dart';
import '../../../../providers/settings/settings_provider.dart';
import 'home_actions.dart';

const ValueKey<String> _compactOverviewLeadKey = ValueKey<String>(
  'homeOverviewCompactLead',
);
const ValueKey<String> _compactOverviewTrailingKey = ValueKey<String>(
  'homeOverviewCompactTrailing',
);
const ValueKey<String> _homeOverviewStatsCardKey = ValueKey<String>(
  'homeOverviewStatsCard',
);
const ValueKey<String> _homeOverviewToggleButtonKey = ValueKey<String>(
  'homeOverviewToggleButton',
);

/// Reads only the derived breakpoint booleans from [MediaQuery.sizeOf] and
/// reuses the same child widget while those booleans stay stable, so the
/// provider-reading inner panel does not rerun on every sub-pixel resize tick.
class HomeOverviewPanel extends StatefulWidget {
  const HomeOverviewPanel({
    super.key,
    @visibleForTesting this.useCompactSummaryOverride,
  });

  final bool? useCompactSummaryOverride;

  @override
  State<HomeOverviewPanel> createState() => _HomeOverviewPanelShellState();
}

class _HomeOverviewPanelShellState extends State<HomeOverviewPanel> {
  ({bool tooNarrow, bool useCompactSummary, bool stackWideSummary})?
  _cachedLayout;
  Widget? _cachedChild;

  @override
  void dispose() {
    _cachedLayout = null;
    _cachedChild = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final layout = (
      tooNarrow: viewport.width < 360,
      useCompactSummary:
          widget.useCompactSummaryOverride ??
          (viewport.height < 760 || viewport.width < 640),
      stackWideSummary: viewport.width < 856,
    );

    if (_cachedLayout == layout && _cachedChild != null) {
      return _cachedChild!;
    }

    final child = layout.tooNarrow
        ? const SizedBox.shrink()
        : _HomeOverviewPanelInner(
            tooNarrow: layout.tooNarrow,
            useCompactSummaryFromViewport: layout.useCompactSummary,
            stackWideSummary: layout.stackWideSummary,
          );
    _cachedLayout = layout;
    _cachedChild = child;
    return child;
  }
}

class _HomeOverviewPanelInner extends ConsumerStatefulWidget {
  const _HomeOverviewPanelInner({
    required this.tooNarrow,
    required this.useCompactSummaryFromViewport,
    required this.stackWideSummary,
  });

  final bool tooNarrow;
  final bool useCompactSummaryFromViewport;
  final bool stackWideSummary;

  @override
  ConsumerState<_HomeOverviewPanelInner> createState() =>
      _HomeOverviewPanelState();
}

class _HomeOverviewPanelState extends ConsumerState<_HomeOverviewPanelInner> {
  int? _cachedSignature;
  Widget? _cachedChild;
  bool _manuallyCollapsed = false;

  @override
  void dispose() {
    _cachedSignature = null;
    _cachedChild = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(homeOverviewProvider);
    final activeActivity = ref.watch(activeCompressionUiModelProvider);
    final viewMode = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.homeViewMode ?? HomeViewMode.grid,
      ),
    );
    final listMode = viewMode == HomeViewMode.list;
    final manualCollapseAvailable =
        !listMode && !widget.useCompactSummaryFromViewport;
    final manuallyCollapsed = manualCollapseAvailable && _manuallyCollapsed;
    final useCompactSummary =
        manuallyCollapsed || listMode || widget.useCompactSummaryFromViewport;
    final stackWideSummary = widget.stackWideSummary;
    final libraryState = ref.watch(
      gameListProvider.select(
        (state) =>
            (isLoading: state.isLoading, error: state.valueOrNull?.error),
      ),
    );
    if (activeActivity != null) {
      return const SizedBox.shrink();
    }
    if (overview.totalGames == 0 &&
        (libraryState.isLoading || libraryState.error != null)) {
      return const SizedBox.shrink();
    }
    if (widget.tooNarrow) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final localeTag = ref.watch(effectiveLocaleProvider).toLanguageTag();
    final label = homePrimaryActionLabel(l10n, overview.primaryAction);
    final icon = homePrimaryActionIcon(overview.primaryAction);
    final signature = Object.hashAll(<Object?>[
      localeTag,
      listMode,
      useCompactSummary,
      stackWideSummary,
      manualCollapseAvailable,
      manuallyCollapsed,
      overview.totalGames,
      overview.readyCount,
      overview.compressedCount,
      overview.protectedCount,
      overview.reclaimableBytes,
      overview.primaryAction,
      libraryState.isLoading,
      libraryState.error != null,
    ]);
    if (_cachedSignature == signature && _cachedChild != null) {
      return _cachedChild!;
    }

    void handlePressed() {
      runHomePrimaryAction(context, ref, overview);
    }

    final panelToggleButton = manualCollapseAvailable
        ? _OverviewPanelToggleButton(
            buttonKey: _homeOverviewToggleButtonKey,
            collapsed: useCompactSummary,
            onPressed: () {
              setState(() {
                _manuallyCollapsed = !manuallyCollapsed;
              });
            },
          )
        : null;

    final child = useCompactSummary
        ? Padding(
            key: const ValueKey<String>('homeOverviewPanelShell'),
            padding: EdgeInsets.fromLTRB(24, listMode ? 8 : 12, 24, 0),
            child: _OverviewPanelFrame(
              decoration: buildAppSurfaceDecoration(),
              toggleButton: panelToggleButton,
              toggleContentClearance: panelToggleButton == null ? 0 : 18,
              padding: EdgeInsets.fromLTRB(18, listMode ? 14 : 16, 18, 14),
              child: _CompactOverviewPanel(
                overview: overview,
                label: label,
                icon: icon,
                onPressed: handlePressed,
              ),
            ),
          )
        : Padding(
            key: const ValueKey<String>('homeOverviewPanelShell'),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: _OverviewPanelFrame(
              decoration: buildAppPanelDecoration(emphasized: true),
              toggleButton: panelToggleButton,
              toggleContentClearance: panelToggleButton == null ? 0 : 12,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              backgroundChildren: [
                Positioned(
                  top: -42,
                  right: -8,
                  child: IgnorePointer(
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.burntSienna.withValues(alpha: 0.22),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              child: stackWideSummary
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _OverviewLead(
                          overview: overview,
                          onPressed: handlePressed,
                          label: label,
                          icon: icon,
                        ),
                        const SizedBox(height: 16),
                        _OverviewStats(overview: overview),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _OverviewLead(
                            overview: overview,
                            onPressed: handlePressed,
                            label: label,
                            icon: icon,
                          ),
                        ),
                        const SizedBox(width: 20),
                        SizedBox(
                          width: 276,
                          child: _OverviewStats(overview: overview),
                        ),
                      ],
                    ),
            ),
          );
    _cachedSignature = signature;
    _cachedChild = child;
    return child;
  }
}

class _CompactOverviewPanel extends StatelessWidget {
  const _CompactOverviewPanel({
    required this.overview,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final HomeOverviewUiModel overview;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionButton = TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 15),
          label: Text(label),
        );
        final lead = _CompactOverviewLead(overview: overview);
        final summaryChips = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _buildCompactChips(l10n),
        );

        if (constraints.maxWidth < 420) {
          return SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeyedSubtree(key: _compactOverviewLeadKey, child: lead),
                const SizedBox(height: 8),
                summaryChips,
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [actionButton]),
              ],
            ),
          );
        }

        return SizedBox(
          width: double.infinity,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: KeyedSubtree(key: _compactOverviewLeadKey, child: lead),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: Align(
                  key: _compactOverviewTrailingKey,
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget?>[
                      ..._buildCompactChips(l10n),
                      actionButton,
                    ].whereType<Widget>().toList(growable: false),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildCompactChips(AppLocalizations l10n) {
    return <Widget>[
      _CompactChip(
        label: l10n.homeOverviewReadyCountLabel,
        value: '${overview.readyCount}',
        color: AppColors.richGold,
      ),
      _CompactChip(
        label: l10n.homeOverviewReclaimableLabel,
        value: formatBytes(l10n, overview.reclaimableBytes),
        color: AppColors.richGold,
      ),
    ];
  }
}

class _OverviewPanelFrame extends StatelessWidget {
  const _OverviewPanelFrame({
    required this.decoration,
    required this.padding,
    required this.child,
    this.toggleButton,
    this.toggleContentClearance = 0,
    this.backgroundChildren = const <Widget>[],
  });

  final Decoration decoration;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final Widget? toggleButton;
  final double toggleContentClearance;
  final List<Widget> backgroundChildren;

  @override
  Widget build(BuildContext context) {
    final effectivePadding = toggleButton == null
        ? padding
        : padding.add(EdgeInsets.only(bottom: toggleContentClearance));
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: decoration,
        child: Stack(
          children: [
            ...backgroundChildren,
            Padding(padding: effectivePadding, child: child),
            if (toggleButton != null)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: toggleButton!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactOverviewLead extends StatelessWidget {
  const _CompactOverviewLead({required this.overview});

  final HomeOverviewUiModel overview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.homeOverviewEyebrow,
          style: AppTypography.label.copyWith(
            color: AppColors.richGold,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _overviewHeadline(l10n, overview),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          _overviewSubtitle(l10n, overview),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _CompactChip extends StatelessWidget {
  const _CompactChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  // Pre-built decoration for the common richGold case — avoids withValues
  // allocations on every build pass.
  static final BoxDecoration _richGoldDecoration = BoxDecoration(
    color: AppColors.richGold.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: AppColors.richGold.withValues(alpha: 0.2)),
  );

  // Per-color cache for callers that pass other colors.
  static final Map<int, BoxDecoration> _decorationCache = {};

  BoxDecoration _decoration() {
    if (color == AppColors.richGold) {
      return _richGoldDecoration;
    }
    return _decorationCache.putIfAbsent(
      color.toARGB32(),
      () => BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _decoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '$label $value',
          style: AppTypography.label.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _OverviewPanelToggleButton extends StatelessWidget {
  const _OverviewPanelToggleButton({
    this.buttonKey,
    required this.collapsed,
    required this.onPressed,
  });

  static const double width = 92;
  static const double height = 30;

  final Key? buttonKey;
  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      width: width,
      height: height,
      child: IconButton(
        key: buttonKey,
        tooltip: collapsed
            ? l10n.homeExpandOverviewTooltip
            : l10n.homeCollapseOverviewTooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.expand(),
        splashRadius: 22,
        visualDensity: VisualDensity.compact,
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.resolveWith(
            (_) => Colors.transparent,
          ),
        ),
        icon: Icon(
          collapsed ? LucideIcons.chevronDown : LucideIcons.chevronUp,
          size: 17,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _OverviewLead extends StatelessWidget {
  const _OverviewLead({
    required this.overview,
    required this.onPressed,
    required this.label,
    required this.icon,
  });

  final HomeOverviewUiModel overview;
  final VoidCallback onPressed;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.homeOverviewEyebrow,
          style: AppTypography.label.copyWith(
            color: AppColors.richGold,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _headline(l10n),
          style: AppTypography.headingLarge.copyWith(
            height: 1.05,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _subtitle(l10n),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(label),
        ),
      ],
    );
  }

  String _headline(AppLocalizations l10n) => _overviewHeadline(l10n, overview);

  String _subtitle(AppLocalizations l10n) => _overviewSubtitle(l10n, overview);
}

class _OverviewStats extends StatelessWidget {
  const _OverviewStats({required this.overview});

  final HomeOverviewUiModel overview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      key: _homeOverviewStatsCardKey,
      decoration: buildAppSurfaceDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OverviewStatRow(
              label: l10n.homeOverviewReadyCountLabel,
              value: '${overview.readyCount}',
              accentColor: AppColors.richGold,
              icon: LucideIcons.archive,
            ),
            const SizedBox(height: 12),
            _OverviewStatRow(
              label: l10n.homeOverviewCompressedCountLabel,
              value: '${overview.compressedCount}',
              accentColor: AppColors.compressed,
              icon: LucideIcons.checkCircle2,
            ),
            const SizedBox(height: 12),
            _OverviewStatRow(
              label: l10n.homeOverviewProtectedCountLabel,
              value: '${overview.protectedCount}',
              accentColor: AppColors.protected,
              icon: LucideIcons.shieldAlert,
            ),
            const SizedBox(height: 12),
            _OverviewStatRow(
              label: l10n.homeOverviewReclaimableLabel,
              value: formatBytes(l10n, overview.reclaimableBytes),
              accentColor: AppColors.richGold,
              icon: LucideIcons.hardDrive,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewStatRow extends StatelessWidget {
  const _OverviewStatRow({
    required this.label,
    required this.value,
    required this.accentColor,
    required this.icon,
  });

  final String label;
  final String value;
  final Color accentColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accentColor.withValues(alpha: 0.2)),
          ),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 14, color: accentColor),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: AppTypography.headingSmall.copyWith(color: accentColor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _overviewHeadline(AppLocalizations l10n, HomeOverviewUiModel overview) {
  if (!overview.hasGames) {
    return l10n.homeOverviewEmptyHeadline;
  }
  if (overview.readyCount > 0) {
    return l10n.homeOverviewReadyHeadline(overview.readyCount);
  }
  if (overview.protectedCount == overview.totalGames) {
    return l10n.homeOverviewProtectedHeadline;
  }
  return l10n.homeOverviewManagedHeadline;
}

String _overviewSubtitle(AppLocalizations l10n, HomeOverviewUiModel overview) {
  if (!overview.hasGames) {
    return l10n.homeOverviewEmptySubtitle;
  }
  if (overview.readyCount > 0) {
    return l10n.homeOverviewReadySubtitle(
      formatBytes(l10n, overview.reclaimableBytes),
    );
  }
  if (overview.protectedCount == overview.totalGames) {
    return l10n.homeOverviewProtectedSubtitle;
  }
  return l10n.homeOverviewManagedSubtitle;
}
