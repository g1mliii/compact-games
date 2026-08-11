import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/localization/app_localization.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/byte_formatting.dart';
import '../../../../../core/utils/date_time_format.dart';
import '../../../../../core/widgets/platform_chip.dart';
import '../../../../../providers/games/library_home_provider.dart';
import '../../../../../providers/games/selected_game_provider.dart';
import '../../../../../providers/games/single_game_provider.dart';
import 'library_home_news_shelf.dart';

/// The no-selection surface for the list view.
///
/// Built entirely from existing cards, typography, spacing, and platform chips
/// — it introduces no new visual primitives and issues no network work of its
/// own. Highlights come from the shared one-pass library reduction.
class LibraryHomeSurface extends ConsumerWidget {
  const LibraryHomeSurface({super.key});

  /// Identifies the surface's scroll view. The highlight cards name games that
  /// also appear in the list beside them, so finders need to say which one
  /// they mean.
  static const Key scrollViewKey = ValueKey<String>('libraryHomeSurface');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(libraryHomeProvider);
    final l10n = context.l10n;

    if (!home.hasGames) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.libraryBig,
                size: 36,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                l10n.libraryHomeEmptyTitle,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.libraryHomeEmptyMessage,
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

    return ListView(
      key: scrollViewKey,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        Text(
          l10n.libraryHomeHighlightsHeading,
          style: AppTypography.label.copyWith(
            color: AppColors.richGold,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        _TotalsRow(
          totalGames: home.totalGames,
          compressedCount: home.compressedCount,
          actualBytesSaved: home.actualBytesSaved,
        ),
        const SizedBox(height: 12),
        _GameHighlightCard(
          icon: LucideIcons.hardDrive,
          label: l10n.libraryHomeLargestInstallLabel,
          gamePath: home.largestInstallPath,
          value: home.largestInstallPath == null
              ? null
              : formatBytes(l10n, home.largestInstallBytes),
        ),
        const SizedBox(height: 8),
        _GameHighlightCard(
          icon: LucideIcons.archive,
          label: l10n.libraryHomeBiggestSaverLabel,
          gamePath: home.biggestSaverPath,
          value: home.biggestSaverPath == null
              ? null
              : formatBytes(l10n, home.biggestSaverBytes),
        ),
        const SizedBox(height: 8),
        _GameHighlightCard(
          icon: LucideIcons.clock,
          label: l10n.libraryHomeRecentlyCompressedLabel,
          gamePath: home.mostRecentCompressedPath,
          value: formatLocalMonthDayTimeOrNull(
            home.mostRecentCompressedAt,
            locale: Localizations.localeOf(context),
          ),
        ),
        const SizedBox(height: 18),
        const LibraryHomeNewsShelf(),
      ],
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.totalGames,
    required this.compressedCount,
    required this.actualBytesSaved,
  });

  final int totalGames;
  final int compressedCount;
  final int actualBytesSaved;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _TotalTile(
          label: l10n.libraryHomeTotalGamesLabel,
          value: '$totalGames',
        ),
        _TotalTile(
          label: l10n.libraryHomeCompressedLabel,
          value: '$compressedCount',
        ),
        _TotalTile(
          label: l10n.libraryHomeSpaceSavedLabel,
          value: formatBytes(l10n, actualBytesSaved),
        ),
      ],
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: buildAppSurfaceDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.label.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A highlight that points at one game. Tapping it selects that game, so the
/// surface doubles as a shortcut into the details pane.
class _GameHighlightCard extends ConsumerWidget {
  const _GameHighlightCard({
    required this.icon,
    required this.label,
    required this.gamePath,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String? gamePath;
  final String? value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final path = gamePath;

    // Reads only the two fields the card draws, so unrelated library updates
    // (sizes, compression progress) do not rebuild it.
    final game = path == null
        ? null
        : ref.watch(
            singleGameProvider(path).select(
              (g) => g == null ? null : (name: g.name, platform: g.platform),
            ),
          );

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  game?.name ?? l10n.libraryHomeHighlightEmpty,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: game == null
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (game != null) ...[
            const SizedBox(width: 10),
            PlatformChip(platform: game.platform, size: PlatformChipSize.sm),
          ],
          if (value != null) ...[
            const SizedBox(width: 10),
            Text(
              value!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );

    if (game == null || path == null) {
      return DecoratedBox(
        decoration: buildAppSurfaceDecoration(),
        child: content,
      );
    }

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: buildAppSurfaceDecoration(),
        child: InkWell(
          borderRadius: appPanelRadius,
          onTap: () => ref.read(selectedGameProvider.notifier).state = path,
          mouseCursor: SystemMouseCursors.click,
          overlayColor: appInteractionOverlay,
          hoverColor: AppColors.hoverSurface,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          child: content,
        ),
      ),
    );
  }
}
