import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../models/game_info.dart';
import '../../../../providers/games/game_list_provider.dart';
import '../../../../services/unsupported_report_sync_service.dart';

/// Shared helper for toggling a game's unsupported status.
/// Used by both the game card context menu and the details info card.
void toggleGameUnsupportedStatus(
  WidgetRef ref,
  BuildContext context,
  GameInfo game, {
  required bool markUnsupported,
}) {
  final bridge = ref.read(rustBridgeServiceProvider);
  if (markUnsupported) {
    bridge.reportUnsupportedGame(game.path);
  } else {
    bridge.unreportUnsupportedGame(game.path);
  }
  ref
      .read(gameListProvider.notifier)
      .updateGameByPath(
        game.path,
        (currentGame) => currentGame.copyWith(isUnsupported: markUnsupported),
      );
  UnsupportedReportSyncService.instance.notePotentialChange(
    ProviderScope.containerOf(context, listen: false),
  );
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        markUnsupported
            ? context.l10n.gameMarkedUnsupported(game.name)
            : context.l10n.gameMarkedSupported(game.name),
      ),
      duration: const Duration(seconds: 2),
    ),
  );
}
