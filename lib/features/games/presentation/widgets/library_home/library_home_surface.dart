import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/localization/app_localization.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../providers/games/library_aggregate_provider.dart';
import 'library_home_news_shelf.dart';
import 'library_home_players_panel.dart';

/// The no-selection surface for the list view.
///
/// Two sections, both about the games rather than about disk space: what is
/// new, and who is playing what right now. The compression figures live in the
/// overview banner above the split view and on every game's own row, so
/// restating them here only cost the scroll it took to reach them.
class LibraryHomeSurface extends ConsumerWidget {
  const LibraryHomeSurface({super.key});

  /// Identifies the surface's scroll view. Its sections name games that also
  /// appear in the list beside them, so finders need to say which one they
  /// mean.
  static const Key scrollViewKey = ValueKey<String>('libraryHomeSurface');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only whether the library is empty: the surface no longer draws a single
    // figure derived from the aggregate.
    final hasGames = ref.watch(
      libraryAggregateProvider.select((home) => home.totalGames > 0),
    );
    final l10n = context.l10n;

    if (!hasGames) {
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
      padding: const EdgeInsets.only(bottom: 20),
      children: const [
        // Both draw their own trailing hairline and collapse to nothing —
        // divider included — when they have nothing to show.
        LibraryHomeNewsShelf(),
        LibraryHomePlayersPanel(),
      ],
    );
  }
}
