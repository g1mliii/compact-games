import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../models/app_settings.dart';
import '../../../../providers/games/selected_game_provider.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../../../../providers/games/game_list_provider.dart';
import 'home_add_game_dialog.dart';

Future<void> reviewFirstEligibleGame(
  WidgetRef ref,
  String? firstReadyPath,
) async {
  if (firstReadyPath == null) {
    return;
  }
  ref.read(gameListProvider.notifier).setSearchQuery('');
  ref.read(selectedGameProvider.notifier).state = firstReadyPath;
  await ref.read(settingsProvider.future);
  ref.read(settingsProvider.notifier).setHomeViewMode(HomeViewMode.list);
}

Future<void> promptAddGame(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<AddItemResult>(
    context: context,
    builder: (_) => const HomeAddGameDialog(),
  );

  if (result == null || !context.mounted) {
    return;
  }

  await submitManualItem(context, ref, result.path, result.mode);
}

Future<void> submitManualItem(
  BuildContext context,
  WidgetRef ref,
  String pathOrExe,
  AddItemMode mode,
) async {
  final l10n = context.l10n;
  try {
    final notifier = ref.read(gameListProvider.notifier);
    final result = mode == AddItemMode.application
        ? await notifier.addApplicationFromPathOrExe(pathOrExe)
        : await notifier.addGameFromPathOrExe(pathOrExe);
    if (!context.mounted) {
      return;
    }

    final message = result.wasAdded
        ? l10n.homeAddedToLibraryMessage(result.game.name)
        : l10n.homeUpdatedInLibraryMessage(result.game.name);
    showHomeMessage(context, message);
  } on ArgumentError catch (error) {
    if (!context.mounted) {
      return;
    }
    showHomeMessage(
      context,
      error.message?.toString() ?? l10n.homeInvalidPathMessage,
    );
  } on StateError catch (error) {
    if (!context.mounted) {
      return;
    }
    showHomeMessage(context, error.message);
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    showHomeMessage(context, l10n.homeFailedToAddGameMessage('$error'));
  }
}

void showHomeMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
