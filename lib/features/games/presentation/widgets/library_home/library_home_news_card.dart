import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/localization/app_localization.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/cover_art_utils.dart';
import '../../../../../core/utils/date_time_format.dart';
import '../../../../../models/game_news_item.dart';
import '../../../../../providers/cover_art/cover_art_provider.dart';
import '../../../../../providers/games/selected_game_provider.dart';
import '../../../../../providers/games/single_game_provider.dart';

/// One news headline, illustrated with the library cover art we already have.
///
/// Deliberately does not download a news thumbnail, and deliberately does not
/// resolve one either: the shelf reads [cachedCoverArtProvider], so a game whose
/// cover the app has not already fetched simply shows a blank tile. Library Home
/// is the default pane, and resolving a dozen 44px thumbnails on open would make
/// merely launching the app do cover-art work the grid has not asked for.
class LibraryHomeNewsCard extends ConsumerWidget {
  const LibraryHomeNewsCard({required this.item, super.key});

  final GameNewsItem item;

  static const double _thumbWidth = 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final gameName = ref.watch(
      singleGameProvider(item.gamePath).select((g) => g?.name),
    );

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: buildAppSurfaceDecoration(),
        child: InkWell(
          borderRadius: appPanelRadius,
          // Selecting the game is the only action: the app does not open a
          // browser, and an embedded web view was explicitly out of scope.
          onTap: gameName == null
              ? null
              : () => ref.read(selectedGameProvider.notifier).state =
                    item.gamePath,
          mouseCursor: SystemMouseCursors.click,
          overlayColor: appInteractionOverlay,
          hoverColor: AppColors.hoverSurface,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NewsThumbnail(gamePath: item.gamePath),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatLocalMonthDayTime(
                          item.publishedAt,
                          locale: Localizations.localeOf(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.label.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        gameName == null
                            ? l10n.libraryHomeNewsSourceSteam
                            : '$gameName · ${l10n.libraryHomeNewsSourceSteam}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.label.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewsThumbnail extends ConsumerWidget {
  const _NewsThumbnail({required this.gamePath});

  final String gamePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = imageProviderFromCover(
      ref.watch(cachedCoverArtProvider(gamePath)),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: LibraryHomeNewsCard._thumbWidth,
        height: double.infinity,
        child: ColoredBox(
          color: AppColors.surfaceElevated,
          child: cover == null
              ? const SizedBox.expand()
              : Image(
                  image: cover,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  // A missing or unreadable cover is a blank tile, never an
                  // error box on the shelf.
                  errorBuilder: (_, _, _) => const SizedBox.expand(),
                ),
        ),
      ),
    );
  }
}
