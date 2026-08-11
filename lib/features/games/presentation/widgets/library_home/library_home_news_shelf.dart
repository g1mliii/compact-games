import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/localization/app_localization.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../providers/games/library_home_news_provider.dart';
import 'library_home_news_card.dart';

/// Horizontally scrolling "What's new" shelf.
///
/// The provider is auto-disposing, so simply mounting this widget is what
/// scopes news fetching to "Library Home is on screen" — there is no timer and
/// nothing to unsubscribe.
class LibraryHomeNewsShelf extends ConsumerWidget {
  const LibraryHomeNewsShelf({super.key});

  static const Key shelfKey = ValueKey<String>('libraryHomeNewsShelf');

  /// Fixed extents keep the shelf off the layout critical path: it never
  /// measures its children, so a resize cannot cascade into image work.
  static const double cardWidth = 260;
  static const double shelfHeight = 108;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final news = ref.watch(libraryHomeNewsProvider);
    final state = news.value;

    // While the cache is still loading there is nothing meaningful to show and
    // a spinner would flash for a few milliseconds, so stay collapsed.
    if (state == null || !state.hasItems) {
      return const SizedBox.shrink();
    }

    return Column(
      key: shelfKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.libraryHomeNewsHeading,
              style: AppTypography.label.copyWith(
                color: AppColors.richGold,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            if (state.isStale) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.libraryHomeNewsStale,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: shelfHeight,
          child: RepaintBoundary(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemExtent: cardWidth,
              addAutomaticKeepAlives: false,
              itemCount: state.items.length,
              itemBuilder: (context, index) {
                final item = state.items[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: LibraryHomeNewsCard(
                    key: ValueKey<String>(item.id),
                    item: item,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
