import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/localization/app_localization.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/cover_art_utils.dart';
import '../../../../../core/utils/number_format.dart';
import '../../../../../models/game_player_count.dart';
import '../../../../../providers/cover_art/cover_art_provider.dart';
import '../../../../../providers/games/library_home_players_provider.dart';
import '../../../../../providers/games/selected_game_provider.dart';
import '../../../../../providers/games/single_game_provider.dart';
import 'library_home_section_header.dart';

/// "Playing now" — Steam's live player counter for the games in this library,
/// busiest first, one row each.
///
/// Includes games installed from anywhere: a title bought outside Steam is
/// usually on Steam too, and its population is the same number. Steam publishes
/// no history for the counter, so each row is the count as of the last refresh
/// and nothing pretends otherwise.
class LibraryHomePlayersPanel extends ConsumerWidget {
  const LibraryHomePlayersPanel({super.key});

  /// Test seam: the panel collapses to nothing when there is nothing to show,
  /// so its presence is the only way to assert on it.
  static const Key panelKey = ValueKey<String>('libraryHomePlayersPanel');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(libraryHomePlayersProvider).value;

    // Nothing meaningful to show while the first fetch is in flight, and a
    // spinner would flash for a moment, so stay collapsed.
    if (state == null || !state.hasItems) {
      return const SizedBox.shrink();
    }

    return Column(
      key: panelKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LibraryHomeSectionHeader(
          title: l10n.libraryHomePlayersHeading,
          staleLabel: l10n.libraryHomePlayersStale,
          isStale: state.isStale,
        ),
        for (final count in state.items) ...[
          const Divider(height: 1, thickness: 1, color: AppColors.borderSubtle),
          _PlayerCountRow(count: count),
        ],
        const Divider(height: 1, thickness: 1, color: AppColors.borderSubtle),
      ],
    );
  }
}

/// One game and its live count. Tapping it selects the game, the same as a row
/// in the list on the left.
class _PlayerCountRow extends ConsumerWidget {
  const _PlayerCountRow({required this.count});

  final GamePlayerCount count;

  static const double _coverWidth = 30;
  static const double _coverHeight = 42;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the name, so unrelated library updates do not rebuild the row.
    final name = ref.watch(
      singleGameProvider(count.gamePath).select((g) => g?.name),
    );
    if (name == null) {
      // The game left the library between the fetch and this frame.
      return const SizedBox.shrink();
    }

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _PlayerCountCover(gamePath: count.gamePath),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            context.l10n.libraryHomePlayersCount(
              formatGroupedInteger(
                count.players,
                locale: Localizations.localeOf(context),
              ),
            ),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.richGold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            ref.read(selectedGameProvider.notifier).state = count.gamePath,
        mouseCursor: SystemMouseCursors.click,
        overlayColor: appInteractionOverlay,
        hoverColor: AppColors.hoverSurface,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        child: content,
      ),
    );
  }
}

/// The game's own artwork, so a row is recognizable before the name is read.
///
/// The same resolving provider the news tiles use, so a game in both sections
/// costs one resolution, not two, and a game with no cover is a flat tile
/// rather than a gap.
class _PlayerCountCover extends ConsumerWidget {
  const _PlayerCountCover({required this.gamePath});

  final String gamePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = imageProviderFromCover(
      ref.watch(coverArtProvider(gamePath)).value,
    );

    return SizedBox(
      width: _PlayerCountRow._coverWidth,
      height: _PlayerCountRow._coverHeight,
      child: ColoredBox(
        color: AppColors.surfaceElevated,
        child: cover == null
            ? const SizedBox.expand()
            : Image(
                image: coverDecodedFor(
                  cover,
                  context: context,
                  logicalWidth: _PlayerCountRow._coverWidth,
                ),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, _, _) => const SizedBox.expand(),
              ),
      ),
    );
  }
}
