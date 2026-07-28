import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../models/game_info.dart';
import '../../../../providers/compression/compression_progress_provider.dart';
import '../../../../providers/games/game_list_provider.dart';
import '../../../../providers/system/platform_shell_provider.dart';
import '../../../../services/platform_shell_service.dart';
import '../../../../services/unsupported_report_sync_service.dart';

Future<void> launchGameFromUi(
  WidgetRef ref,
  BuildContext context,
  GameInfo game,
) async {
  if (ref.read(gameCompressionBusyProvider(game.path))) {
    return;
  }
  final shell = ref.read(platformShellServiceProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(context.l10n.gameLaunchAttempting(game.name)),
        duration: const Duration(seconds: 3),
      ),
    );

  final result = await shell.launchGame(game);
  if (!context.mounted || result == GameLaunchResult.requested) {
    return;
  }
  if (result == GameLaunchResult.selectionCancelled) {
    messenger?.hideCurrentSnackBar();
    return;
  }

  // `requested` and `selectionCancelled` returned above, so only the two
  // failure outcomes reach here.
  final failureMessage = result == GameLaunchResult.targetNotFound
      ? context.l10n.gameLaunchTargetNotFound(game.name)
      : context.l10n.gameLaunchFailed(game.name);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(failureMessage),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: context.l10n.commonOpenFolder,
          onPressed: () => shell.openFolder(game.path),
        ),
      ),
    );
}

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
