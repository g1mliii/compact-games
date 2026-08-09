import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/compression/compression_provider.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../../../../providers/update/update_provider.dart';
import '../../../../providers/update/update_status_presentation.dart';
import '../widgets/scaled_switch_row.dart';
import '../widgets/settings_section_card.dart';

class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selfUpdatesEnabled = ref.watch(selfUpdatesEnabledProvider);
    final autoCheck = ref.watch(
      settingsProvider.select((s) => s.value?.settings.autoCheckUpdates),
    );
    final updateState = ref.watch(updateProvider.select((s) => s.value));
    final hasActiveCompression = ref.watch(
      compressionProvider.select((s) => s.hasActiveJob),
    );

    if (autoCheck == null) return const SizedBox.shrink();

    final update = updateState ?? const UpdateState();
    final status = update.status;
    final info = update.info;
    final error = update.error;
    final presentation = describeUpdateStatus(
      update,
      l10n,
      installBlocked: hasActiveCompression,
    );
    final action = presentation.action;

    return SettingsSectionCard(
      icon: LucideIcons.info,
      title: l10n.settingsAboutSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.settingsAboutVersionLabel,
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(width: 8),
              Text(
                AppConstants.appVersion,
                style: AppTypography.mono.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.settingsAboutCompactGuiCredit,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.settingsAboutSteamGridDbCredit,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          if (!selfUpdatesEnabled) ...[
            _buildStatusRow(
              LucideIcons.badgeCheck,
              l10n.settingsAboutUpdatesManagedBySteam,
              AppColors.success,
            ),
          ] else ...[
            ScaledSwitchRow(
              label: l10n.settingsAboutAutoCheckUpdatesLabel,
              value: autoCheck,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setAutoCheckUpdates(v),
              enableLabelSurfaceHover: false,
              showLabelSurfaceDecoration: false,
            ),
            const SizedBox(height: 12),
          ],
          if (selfUpdatesEnabled && status == UpdateStatus.checking)
            _SpinningStatusRow(
              label: presentation.message,
              color: presentation.color,
            ),

          if (selfUpdatesEnabled &&
              status == UpdateStatus.error &&
              error != null) ...[
            _buildStatusRow(
              presentation.icon,
              presentation.message,
              presentation.color,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            UpdateActionButton(action: action!),
          ],

          if (selfUpdatesEnabled && status == UpdateStatus.idle)
            UpdateActionButton(action: action!),

          if (selfUpdatesEnabled &&
              status == UpdateStatus.available &&
              info != null) ...[
            _buildStatusRow(
              presentation.icon,
              presentation.message,
              presentation.color,
            ),
            if (info.publishedAt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                l10n.settingsAboutReleasedLabel(info.publishedAt),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  info.releaseNotes,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 12),
            UpdateActionButton(action: action!),
          ],

          if (selfUpdatesEnabled && status == UpdateStatus.downloading) ...[
            _SpinningStatusRow(
              label: presentation.message,
              color: presentation.color,
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              backgroundColor: AppColors.surfaceVariant,
              color: AppColors.richGold,
            ),
          ],

          if (selfUpdatesEnabled && status == UpdateStatus.downloaded) ...[
            _buildStatusRow(
              presentation.icon,
              presentation.message,
              presentation.color,
            ),
            const SizedBox(height: 12),
            UpdateActionButton(action: action!),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Row with a continuously-rotating loader icon. Extracted as a StatefulWidget
/// so the AnimationController lifecycle is managed independently of the parent.
class _SpinningStatusRow extends StatefulWidget {
  const _SpinningStatusRow({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  State<_SpinningStatusRow> createState() => _SpinningStatusRowState();
}

class _SpinningStatusRowState extends State<_SpinningStatusRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        RotationTransition(
          turns: _controller,
          child: Icon(LucideIcons.loader2, size: 16, color: widget.color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.label,
            style: AppTypography.bodyMedium.copyWith(color: widget.color),
          ),
        ),
      ],
    );
  }
}
