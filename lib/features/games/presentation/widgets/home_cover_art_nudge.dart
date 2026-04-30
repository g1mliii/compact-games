import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../models/app_settings.dart';
import '../../../../providers/settings/settings_provider.dart';

/// Tracks whether the user has dismissed the nudge this session.
/// Resets on app restart — intentional, since they may forget between sessions.
final _nudgeDismissedProvider = StateProvider<bool>((ref) => false);

/// Inline banner shown only when own-key mode is selected without a key.
class HomeCoverArtNudge extends ConsumerWidget {
  const HomeCoverArtNudge({super.key});

  static const double _stackedBreakpoint = 420;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(_nudgeDismissedProvider);
    if (dismissed) return const SizedBox.shrink();

    final coverSettings = ref.watch(
      settingsProvider.select((s) {
        final settings = s.valueOrNull?.settings;
        if (settings == null) {
          return null;
        }
        return (
          hasKey: (settings.steamGridDbApiKey ?? '').isNotEmpty,
          mode: settings.coverArtProviderMode,
        );
      }),
    );
    if (coverSettings == null ||
        coverSettings.mode == CoverArtProviderMode.bundledProxy ||
        coverSettings.hasKey) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: _NudgeContent(
              onDismiss: () =>
                  ref.read(_nudgeDismissedProvider.notifier).state = true,
            ),
          ),
        ),
      ),
    );
  }
}

class _NudgeContent extends StatelessWidget {
  const _NudgeContent({required this.onDismiss});

  final VoidCallback onDismiss;

  static final _messageStyle = AppTypography.bodySmall.copyWith(
    color: AppColors.textSecondary,
  );
  static final _settingsLabelStyle = AppTypography.bodySmall.copyWith(
    color: AppColors.accent,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = Expanded(
      child: Text(l10n.homeCoverArtNudgeMessage, style: _messageStyle),
    );
    final settingsButton = TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
      child: Text(l10n.homeGoToSettingsButton, style: _settingsLabelStyle),
    );
    final dismissButton = IconButton(
      tooltip: l10n.commonDismissTooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: appDesktopControlMin,
        minHeight: appDesktopControlMin,
      ),
      icon: const Icon(LucideIcons.x, size: 14, color: AppColors.textMuted),
      onPressed: onDismiss,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < HomeCoverArtNudge._stackedBreakpoint;

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      LucideIcons.imageOff,
                      size: 15,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 10),
                  message,
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.end,
                  children: [settingsButton, dismissButton],
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            const Icon(
              LucideIcons.imageOff,
              size: 15,
              color: AppColors.warning,
            ),
            const SizedBox(width: 10),
            message,
            const SizedBox(width: 10),
            settingsButton,
            const SizedBox(width: 4),
            dismissButton,
          ],
        );
      },
    );
  }
}
