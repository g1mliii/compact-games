import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_formatting.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../providers/compression/compression_state.dart';
import '../../../../providers/restore/restore_games_provider.dart';
import '../../../../services/uninstall_service.dart';
import '../widgets/settings_section_card.dart';

class RestoreGamesSection extends ConsumerWidget {
  const RestoreGamesSection({super.key});

  static const ValueKey<String> restoreButtonKey = ValueKey<String>(
    'settingsRestoreAllButton',
  );
  static const ValueKey<String> uninstallButtonKey = ValueKey<String>(
    'settingsRestoreUninstallButton',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(restoreGamesProvider);
    final plan = state.plan;

    return SettingsSectionCard(
      icon: LucideIcons.hardDrive,
      title: l10n.settingsRestoreSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsRestoreDescription,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          if (state.isLoading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              l10n.settingsRestoreChecking,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ] else ...[
            if (state.error != null) ...[
              _StatusRow(
                icon: LucideIcons.alertCircle,
                color: AppColors.error,
                text: l10n.settingsRestoreLoadFailed(state.error!),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: state.isRestoring
                    ? null
                    : () => ref.read(restoreGamesProvider.notifier).loadPlan(),
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: Text(l10n.settingsRestoreRefresh),
              ),
            ],
            if (state.isRestoring) ...[
              LinearProgressIndicator(
                value: state.totalGames == 0
                    ? null
                    : state.completedGames / state.totalGames,
              ),
              const SizedBox(height: 8),
              _StatusRow(
                icon: LucideIcons.loader2,
                color: AppColors.richGold,
                text: l10n.settingsRestoreProgress(
                  state.completedGames,
                  state.totalGames,
                ),
              ),
            ],
            if (!state.isRestoring &&
                plan != null &&
                plan.games.isEmpty &&
                !state.restoreCompleted)
              _StatusRow(
                icon: LucideIcons.checkCircle,
                color: AppColors.textSecondary,
                text: l10n.settingsRestoreNoGames,
              ),
            if (!state.isRestoring &&
                plan != null &&
                plan.games.isNotEmpty) ...[
              Text(
                l10n.settingsRestoreSummary(
                  plan.gameCount,
                  formatBytes(l10n, plan.requiredBytes),
                ),
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.settingsRestoreLongRuntime,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(height: 10),
              for (final drive in plan.drives)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: _StatusRow(
                    icon: drive.hasEnoughSpace
                        ? LucideIcons.hardDrive
                        : LucideIcons.alertTriangle,
                    color: drive.hasEnoughSpace
                        ? AppColors.textSecondary
                        : AppColors.error,
                    text: l10n.settingsRestoreDriveSpace(
                      drive.drive,
                      formatBytes(l10n, drive.requiredBytes),
                      formatBytes(l10n, drive.availableBytes),
                    ),
                  ),
                ),
              if (!plan.hasEnoughSpace) ...[
                const SizedBox(height: 4),
                _StatusRow(
                  icon: LucideIcons.alertTriangle,
                  color: AppColors.error,
                  text: l10n.settingsRestoreDriveInsufficient,
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                key: restoreButtonKey,
                onPressed: state.canStart
                    ? () => _confirmRestore(context, ref)
                    : null,
                icon: const Icon(LucideIcons.rotateCcw, size: 16),
                label: Text(l10n.settingsRestoreAction),
              ),
            ],
            if (state.failures.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                l10n.settingsRestoreFailuresTitle,
                style: AppTypography.headingSmall.copyWith(
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 8),
              for (final failure in state.failures)
                _FailureCard(failure: failure),
            ],
            if (state.skippedGames.isNotEmpty) ...[
              const SizedBox(height: 10),
              _StatusRow(
                icon: LucideIcons.alertTriangle,
                color: AppColors.warning,
                text: l10n.settingsRestoreSkipped(state.skippedGames.length),
              ),
            ],
            if (state.canOfferUninstall) ...[
              _StatusRow(
                icon: LucideIcons.checkCircle,
                color: AppColors.success,
                text: l10n.settingsRestoreSuccess,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: uninstallButtonKey,
                onPressed: () => _launchUninstaller(context, ref),
                icon: const Icon(LucideIcons.trash2, size: 16),
                label: Text(l10n.settingsRestoreUninstallAction),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRestore(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final plan = ref.read(restoreGamesProvider).plan;
    if (plan == null || plan.games.isEmpty || !plan.hasEnoughSpace) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsRestoreConfirmTitle),
        content: Text(
          l10n.settingsRestoreConfirmBody(
            plan.gameCount,
            formatBytes(l10n, plan.requiredBytes),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsRestoreAction),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(restoreGamesProvider.notifier).restoreAll();
    }
  }

  Future<void> _launchUninstaller(BuildContext context, WidgetRef ref) async {
    final launched = await ref.read(uninstallServiceProvider).launch();
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsRestoreUninstallNotFound)),
      );
    }
  }
}

class _FailureCard extends ConsumerWidget {
  const _FailureCard({required this.failure});

  final RestoreFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(failure.game.gameName, style: AppTypography.bodyMedium),
          const SizedBox(height: 3),
          Text(
            failure.game.gamePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.mono.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _failureMessage(l10n, failure.reason),
            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => ref
                    .read(restoreGamesProvider.notifier)
                    .retryFailure(failure.game.gamePath),
                child: Text(l10n.commonRetry),
              ),
              TextButton(
                onPressed: () => ref
                    .read(restoreGamesProvider.notifier)
                    .skipFailure(failure.game.gamePath),
                child: Text(l10n.settingsRestoreSkip),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _failureMessage(AppLocalizations l10n, RestoreFailureReason reason) {
  return switch (reason) {
    RestoreAlreadyQueued() => l10n.settingsRestoreFailureAlreadyQueued,
    RestoreEndedWith(:final status) => switch (status) {
      CompressionJobStatus.cancelled => l10n.settingsRestoreFailureCancelled,
      CompressionJobStatus.failed => l10n.settingsRestoreFailureFailed,
      _ => l10n.settingsRestoreFailureIncomplete,
    },
    RestoreThrew(:final error) => l10n.settingsRestoreFailureError(error),
  };
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
