import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localization.dart';
import '../cover_art/cover_art_provider.dart';
import 'game_list_provider.dart';

/// Shared refresh-and-invalidate logic used by both the home header and
/// inventory screen.  Avoids duplicating the same provider reads and
/// cover-art cache invalidation in two places.
/// Returns whether the reload actually ran; false means a concurrent refresh
/// owned it, which callers reporting an outcome to the user must not treat as
/// a completed rescan.
Future<bool> refreshGamesAndInvalidateCovers(WidgetRef ref) async {
  final refreshed = await ref.read(gameListProvider.notifier).refresh();

  final games = ref.read(gameListProvider).value?.games ?? const [];
  if (games.isEmpty) return refreshed;

  final paths = games.map((game) => game.path).toList(growable: false);
  final coverArtService = ref.read(coverArtServiceProvider);
  final placeholders = coverArtService.placeholderRefreshCandidates(paths);
  if (placeholders.isEmpty) return refreshed;

  coverArtService.clearLookupCaches();
  coverArtService.invalidateCoverForGames(placeholders);
  for (final path in placeholders) {
    ref.invalidate(coverArtProvider(path));
  }
  return refreshed;
}

/// Run a library refresh with immediate and terminal user feedback.
///
/// A full metadata scan can take time on large compressed libraries. Keep one
/// persistent progress message visible until it finishes, then replace it with
/// the actual outcome so the refresh action never appears inert.
Future<void> refreshGamesWithFeedback(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l10n.activityScanningFiles),
          ],
        ),
      ),
    );

  final refreshed = await refreshGamesAndInvalidateCovers(ref);
  if (messenger.mounted) {
    messenger.hideCurrentSnackBar();
  }
  if (!context.mounted) return;

  final listState = ref.read(gameListProvider);
  final failed = listState.hasError || listState.value?.error != null;
  final message = !refreshed
      ? l10n.inventoryRescanAlreadyRunning
      : failed
      ? l10n.inventoryRescanFailed
      : l10n.inventoryRescanCompleted;
  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}
