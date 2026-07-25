import 'package:compact_games/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_formatting.dart';
import '../../../../providers/compression/compression_progress_provider.dart';
import '../../../../providers/games/home_overview_provider.dart';
import 'home_actions.dart';

const ValueKey<String> _compactOverviewLeadKey = ValueKey<String>(
  'homeOverviewCompactLead',
);
const ValueKey<String> _compactOverviewTrailingKey = ValueKey<String>(
  'homeOverviewCompactTrailing',
);
const ValueKey<String> _homeOverviewDismissButtonKey = ValueKey<String>(
  'homeOverviewDismissButton',
);

/// Tracks whether the user dismissed the overview in this app process.
///
/// This intentionally is not persisted or auto-disposed, so navigating away
/// from home or hiding the window to the tray does not resurrect the panel.
final _overviewDismissedProvider = StateProvider<bool>((ref) => false);

/// Responsive shell that avoids subscribing the provider-reading content to
/// continuous resize updates.
class HomeOverviewPanel extends StatelessWidget {
  const HomeOverviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 360) {
      return const SizedBox.shrink();
    }
    return const _HomeOverviewPanelContent();
  }
}

class _HomeOverviewPanelContent extends ConsumerWidget {
  const _HomeOverviewPanelContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(activeCompressionUiModelProvider) != null) {
      return const SizedBox.shrink();
    }
    if (ref.watch(_overviewDismissedProvider)) {
      return const SizedBox.shrink();
    }

    final overview = ref.watch(homeOverviewProvider);
    if (overview.readyCount == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      key: const ValueKey<String>('homeOverviewPanelShell'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: buildAppSurfaceDecoration(),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 50, 14),
                child: _CompactOverviewPanel(
                  overview: overview,
                  onPressed: () async {
                    await reviewFirstEligibleGame(ref, overview.firstReadyPath);
                  },
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  key: _homeOverviewDismissButtonKey,
                  tooltip: context.l10n.commonDismissTooltip,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: appDesktopControlMin,
                    minHeight: appDesktopControlMin,
                  ),
                  icon: const Icon(
                    LucideIcons.x,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () {
                    ref.read(_overviewDismissedProvider.notifier).state = true;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactOverviewPanel extends StatelessWidget {
  const _CompactOverviewPanel({
    required this.overview,
    required this.onPressed,
  });

  final HomeOverviewUiModel overview;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionButton = TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(LucideIcons.archive, size: 15),
          label: Text(l10n.homePrimaryReviewEligible),
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
                    children: [..._buildCompactChips(l10n), actionButton],
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
      ),
      _CompactChip(
        label: l10n.homeOverviewReclaimableLabel,
        value: formatBytes(l10n, overview.reclaimableBytes),
      ),
    ];
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
          l10n.homeOverviewReadyHeadline(overview.readyCount),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.homeOverviewReadySubtitle(
            formatBytes(l10n, overview.reclaimableBytes),
          ),
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
  const _CompactChip({required this.label, required this.value});

  final String label;
  final String value;

  static final BoxDecoration _decoration = BoxDecoration(
    color: AppColors.richGold.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: AppColors.richGold.withValues(alpha: 0.2)),
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _decoration,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '$label $value',
          style: AppTypography.label.copyWith(
            color: AppColors.richGold,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
