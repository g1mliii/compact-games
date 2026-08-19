import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/localization/app_localization.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/cover_art_utils.dart';
import '../../../../../core/utils/date_time_format.dart';
import '../../../../../models/game_news_item.dart';
import '../../../../../providers/cover_art/cover_art_provider.dart';
import '../../../../../providers/games/single_game_provider.dart';
import 'library_home_news_reader.dart';

/// One news headline, drawn as a rectangle with the game's cover art bleeding
/// to its edges and the headline overlaid on a gradient scrim.
///
/// The artwork is the card here rather than a 44px nicety, so this watches the
/// resolving [coverArtProvider] instead of peeking the in-memory cache: peeking
/// left most tiles blank until something else in the app happened to resolve
/// that game's cover, which read as broken. The shelf builds lazily, so only
/// the handful of cards actually on screen ever ask for a cover.
class LibraryHomeNewsCard extends ConsumerWidget {
  const LibraryHomeNewsCard({required this.item, super.key});

  final GameNewsItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final gameName = ref.watch(
      singleGameProvider(item.gamePath).select((g) => g?.name),
    );
    final byline = newsByline(l10n, gameName);

    return Stack(
      fit: StackFit.expand,
      children: [
        _NewsBackdrop(gamePath: item.gamePath),
        const DecoratedBox(decoration: BoxDecoration(gradient: _scrimGradient)),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                formatLocalMonthDayTime(
                  item.publishedAt,
                  locale: Localizations.localeOf(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(
                  color: AppColors.textPrimary.withValues(alpha: 0.72),
                  shadows: _textShadows,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  shadows: _textShadows,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                byline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                  shadows: _textShadows,
                ),
              ),
            ],
          ),
        ),
        // A tile that only reads as a picture gives no sign it can be opened.
        const Positioned(
          top: 8,
          right: 8,
          child: Icon(
            LucideIcons.bookOpen,
            size: 13,
            color: AppColors.textSecondary,
            shadows: _textShadows,
          ),
        ),
        // Above the artwork so hover and press feedback are not painted
        // underneath it.
        Positioned.fill(
          child: Tooltip(
            message: l10n.libraryHomeNewsReadAction,
            waitDuration: const Duration(milliseconds: 600),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                // Reading the announcement is the point of the shelf; selecting
                // the game is what the highlight rows below already do.
                onTap: () => showLibraryHomeNewsReader(context, item),
                mouseCursor: SystemMouseCursors.click,
                overlayColor: appInteractionOverlay,
                hoverColor: AppColors.hoverSurface,
                highlightColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NewsBackdrop extends ConsumerWidget {
  const _NewsBackdrop({required this.gamePath});

  final String gamePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = imageProviderFromCover(
      ref.watch(coverArtProvider(gamePath)).value,
    );

    if (cover == null) {
      return const DecoratedBox(
        decoration: BoxDecoration(gradient: _placeholderGradient),
      );
    }

    return Image(
      image: coverDecodedFor(
        cover,
        context: context,
        logicalWidth: libraryHomeNewsCardWidth,
      ),
      fit: BoxFit.cover,
      // Library capsules are portrait, so a wide tile shows a band of one.
      // Bias it upward, where the key art and logo usually sit.
      alignment: const Alignment(0, -0.35),
      filterQuality: FilterQuality.low,
      // A missing or unreadable cover falls back to the flat tile, never an
      // error box on the shelf.
      errorBuilder: (_, _, _) => const DecoratedBox(
        decoration: BoxDecoration(gradient: _placeholderGradient),
      ),
    );
  }
}

/// Who a news item is about and where it came from: `Portal 2 · Steam`, or just
/// the source while the game's name is still resolving.
///
/// Shared with the reader so the tile and the panel it opens cannot disagree
/// about the separator or the order.
String newsByline(AppLocalizations l10n, String? gameName) {
  return gameName == null
      ? l10n.libraryHomeNewsSourceSteam
      : '$gameName · ${l10n.libraryHomeNewsSourceSteam}';
}

/// Width of one tile. Lives with the card rather than the shelf so the card can
/// size its own artwork without asking its parent.
const double libraryHomeNewsCardWidth = 232;

/// Darkens the artwork from the bottom up so the headline never sits on raw
/// key art. The top stays mostly clear, which is where the capsule art reads.
const LinearGradient _scrimGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: <Color>[Color(0x33121B24), Color(0x99121B24), Color(0xF2121B24)],
  stops: <double>[0, 0.42, 1],
);

/// What a card with no cover art shows: the same tile, minus the picture.
const LinearGradient _placeholderGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[AppColors.surfaceVariant, AppColors.surfaceHero],
);

/// Keeps text legible over a bright frame of key art without a heavier scrim.
const List<Shadow> _textShadows = <Shadow>[
  Shadow(color: Color(0xCC0B1119), blurRadius: 6),
];
