import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/compression/compression_progress_provider.dart';
import '../../../../providers/compression/compression_provider.dart';
import '../../../../providers/update/update_provider.dart';
import '../../../../providers/update/update_status_presentation.dart';
import '../../../../src/rust/api/update.dart' show UpdateCheckResult;

const ValueKey<String> homeUpdateBannerKey = ValueKey<String>(
  'homeUpdateBanner',
);
const ValueKey<String> homeUpdateActionKey = ValueKey<String>(
  'homeUpdateAction',
);
const ValueKey<String> homeUpdateDismissKey = ValueKey<String>(
  'homeUpdateDismiss',
);
const ValueKey<String> homeUpdateProgressKey = ValueKey<String>(
  'homeUpdateProgress',
);

/// Version *and* status of the last dismissal.
///
/// Keying on the version alone would let a dismissed "update available" notice
/// also swallow the download failure that follows it for the same version.
typedef _DismissedUpdate = ({String version, UpdateStatus status});

final _dismissedUpdateProvider = StateProvider<_DismissedUpdate?>(
  (ref) => null,
);

/// Dismissible statuses. `downloaded` is dismissible even though it stays
/// actionable: it otherwise persists for the whole session and would
/// permanently outrank every other home attention surface. `downloading` is the
/// one supported status that is not dismissible — it clears itself.
bool _canBeDismissed(UpdateStatus status) {
  return status == UpdateStatus.available ||
      status == UpdateStatus.downloaded ||
      status == UpdateStatus.error;
}

/// What the update banner should show, or null when another home attention
/// surface wins. Carrying the payload keeps the showable-update preconditions
/// in one place instead of restating them in the widget.
typedef HomeUpdateBannerModel = ({UpdateState state, UpdateCheckResult info});

final homeUpdateBannerModelProvider = Provider<HomeUpdateBannerModel?>((ref) {
  if (!ref.watch(selfUpdatesEnabledProvider) ||
      // Selected, so bucketed compression progress does not re-run this body.
      ref.watch(activeCompressionUiModelProvider.select((m) => m != null))) {
    return null;
  }

  final update = ref.watch(updateProvider.select((state) => state.value));
  final info = update?.info;
  if (update == null || info == null) {
    return null;
  }

  final status = update.status;
  final dismissible = _canBeDismissed(status);
  if (!dismissible && status != UpdateStatus.downloading) {
    return null;
  }

  final model = (state: update, info: info);
  if (!dismissible) {
    return model;
  }
  final dismissed = ref.watch(_dismissedUpdateProvider);
  final isDismissed =
      dismissed != null &&
      dismissed.version == info.latestVersion &&
      dismissed.status == status;
  return isDismissed ? null : model;
});

/// Actionable update surface. It is built only inside the visible MaterialApp
/// subtree, so tray hide releases the entire widget and render tree.
class HomeUpdateBanner extends ConsumerWidget {
  const HomeUpdateBanner({super.key});

  static const double _stackedBreakpoint = 520;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(homeUpdateBannerModelProvider);
    if (model == null) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final update = model.state;
    final info = model.info;
    final status = update.status;
    final isDownloading = status == UpdateStatus.downloading;

    final presentation = describeUpdateStatus(
      update,
      l10n,
      installBlocked: ref.watch(
        compressionProvider.select((s) => s.hasActiveJob),
      ),
    );
    final action = presentation.action;
    final message = presentation.message;
    final statusIcon = presentation.icon;
    final statusColor = presentation.color;
    final canDismiss = _canBeDismissed(status);

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: DecoratedBox(
          key: homeUpdateBannerKey,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textAndProgress = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (isDownloading) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(
                        key: homeUpdateProgressKey,
                        minHeight: 3,
                        backgroundColor: AppColors.surface,
                        color: AppColors.richGold,
                      ),
                    ],
                  ],
                );
                final actionButton = action == null
                    ? null
                    : UpdateActionButton(
                        key: homeUpdateActionKey,
                        action: action,
                        iconSize: 15,
                      );
                final dismissButton = !canDismiss
                    ? null
                    : IconButton(
                        key: homeUpdateDismissKey,
                        tooltip: l10n.commonDismissTooltip,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: appDesktopControlMin,
                          minHeight: appDesktopControlMin,
                        ),
                        icon: const Icon(
                          LucideIcons.x,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () {
                          ref.read(_dismissedUpdateProvider.notifier).state = (
                            version: info.latestVersion,
                            status: status,
                          );
                        },
                      );

                if (constraints.maxWidth < _stackedBreakpoint) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              statusIcon,
                              size: 16,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: textAndProgress),
                        ],
                      ),
                      if (actionButton != null || dismissButton != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [?actionButton, ?dismissButton],
                          ),
                        ),
                      ],
                    ],
                  );
                }

                return Row(
                  children: [
                    Icon(statusIcon, size: 16, color: statusColor),
                    const SizedBox(width: 10),
                    Expanded(child: textAndProgress),
                    if (actionButton != null) ...[
                      const SizedBox(width: 10),
                      actionButton,
                    ],
                    if (dismissButton != null) ...[
                      const SizedBox(width: 4),
                      dismissButton,
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
