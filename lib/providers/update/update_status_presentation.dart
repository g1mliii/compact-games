import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import 'update_provider.dart';

@immutable
class UpdateAction {
  const UpdateAction({
    required this.invoke,
    required this.label,
    required this.icon,
    this.enabled = true,
  });

  final Future<void> Function(UpdateNotifier notifier) invoke;
  final String label;
  final IconData icon;

  /// False when the action is offered but temporarily blocked, so both surfaces
  /// disable the same button instead of each inventing its own gate.
  final bool enabled;

  void run(UpdateNotifier notifier) => unawaited(invoke(notifier));
}

/// The one button both update surfaces render for [UpdateAction].
class UpdateActionButton extends ConsumerWidget {
  const UpdateActionButton({
    super.key,
    required this.action,
    this.iconSize = 16,
  });

  final UpdateAction action;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      onPressed: action.enabled
          ? () => action.run(ref.read(updateProvider.notifier))
          : null,
      icon: Icon(action.icon, size: iconSize),
      label: Text(action.label),
    );
  }
}

@immutable
class UpdateStatusPresentation {
  const UpdateStatusPresentation({
    required this.message,
    required this.icon,
    required this.color,
    this.action,
  });

  final String message;
  final IconData icon;
  final Color color;
  final UpdateAction? action;
}

/// Single owner of the update status -> (message, icon, action) mapping.
///
/// Both update surfaces — the home banner and the settings About section —
/// render from this, so adding a status or renaming a key cannot leave one of
/// them showing a stale label or offering an action the other does not.
///
/// [installBlocked] is resolved here rather than at each call site, so a surface
/// cannot offer an enabled install button that the notifier would silently drop.
UpdateStatusPresentation describeUpdateStatus(
  UpdateState state,
  AppLocalizations l10n, {
  bool installBlocked = false,
}) {
  switch (state.status) {
    case UpdateStatus.idle:
      return UpdateStatusPresentation(
        message: '',
        icon: LucideIcons.refreshCw,
        color: AppColors.textSecondary,
        action: UpdateAction(
          invoke: (notifier) => notifier.checkForUpdate(),
          label: l10n.settingsAboutCheckForUpdatesAction,
          icon: LucideIcons.refreshCw,
        ),
      );
    case UpdateStatus.checking:
      return UpdateStatusPresentation(
        message: l10n.settingsAboutCheckingForUpdatesStatus,
        icon: LucideIcons.loader2,
        color: AppColors.textSecondary,
      );
    case UpdateStatus.available:
      return UpdateStatusPresentation(
        message: l10n.settingsAboutUpdateAvailableStatus(
          state.info?.latestVersion ?? '',
        ),
        icon: LucideIcons.download,
        color: AppColors.success,
        action: UpdateAction(
          invoke: (notifier) => notifier.downloadUpdate(),
          label: l10n.settingsAboutDownloadUpdateAction,
          icon: LucideIcons.download,
        ),
      );
    case UpdateStatus.downloading:
      return UpdateStatusPresentation(
        message: l10n.settingsAboutDownloadingUpdateStatus,
        icon: LucideIcons.download,
        color: AppColors.richGold,
      );
    case UpdateStatus.downloaded:
      return UpdateStatusPresentation(
        message: l10n.settingsAboutUpdateReadyToInstallStatus,
        icon: LucideIcons.checkCircle,
        color: AppColors.success,
        // Installing restarts the app, so it waits for compression to end.
        action: UpdateAction(
          invoke: (notifier) => notifier.launchInstaller(),
          label: installBlocked
              ? l10n.settingsAboutWaitingForCompressionStatus
              : l10n.settingsAboutInstallUpdateAndRestartAction,
          icon: LucideIcons.rocket,
          enabled: !installBlocked,
        ),
      );
    case UpdateStatus.error:
      // Without release metadata there is nothing to retry downloading, so the
      // only way forward is a fresh check.
      final canRetryDownload = state.info != null;
      return UpdateStatusPresentation(
        message: l10n.settingsAboutUpdateFailedTitle,
        icon: LucideIcons.alertCircle,
        color: AppColors.error,
        action: UpdateAction(
          invoke: canRetryDownload
              ? (notifier) => notifier.downloadUpdate()
              : (notifier) => notifier.checkForUpdate(),
          label: canRetryDownload
              ? l10n.settingsAboutRetryDownloadAction
              : l10n.settingsAboutRetryCheckAction,
          icon: canRetryDownload ? LucideIcons.download : LucideIcons.refreshCw,
        ),
      );
  }
}
