import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/compression/compression_provider.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../../../../providers/update/update_provider.dart';
import '../widgets/scaled_switch_row.dart';
import '../widgets/settings_section_card.dart';

class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoCheck = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.settings.autoCheckUpdates),
    );
    final updateState = ref.watch(updateProvider.select((s) => s.valueOrNull));
    final hasActiveCompression = ref.watch(
      compressionProvider.select((s) => s.hasActiveJob),
    );

    if (autoCheck == null) return const SizedBox.shrink();

    final status = updateState?.status ?? UpdateStatus.idle;
    final info = updateState?.info;
    final error = updateState?.error;
    final canRetryDownload = info != null;

    return SettingsSectionCard(
      icon: LucideIcons.info,
      title: 'About',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Version', style: AppTypography.bodyMedium),
              const SizedBox(width: 8),
              Text(
                AppConstants.appVersion,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ScaledSwitchRow(
            label: 'Check for updates automatically',
            value: autoCheck,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setAutoCheckUpdates(v),
            enableLabelSurfaceHover: false,
            showLabelSurfaceDecoration: false,
          ),
          const SizedBox(height: 12),
          if (status == UpdateStatus.checking)
            const _SpinningStatusRow(
              label: 'Checking for updates...',
              color: AppColors.textSecondary,
            ),

          if (status == UpdateStatus.error && error != null) ...[
            _buildStatusRow(
              LucideIcons.alertCircle,
              'Update failed',
              AppColors.error,
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
            FilledButton.icon(
              onPressed: () => canRetryDownload
                  ? ref.read(updateProvider.notifier).downloadUpdate()
                  : ref.read(updateProvider.notifier).checkForUpdate(),
              icon: Icon(
                canRetryDownload ? LucideIcons.download : LucideIcons.refreshCw,
                size: 16,
              ),
              label: Text(canRetryDownload ? 'Retry Download' : 'Retry Check'),
            ),
          ],

          if (status == UpdateStatus.idle)
            FilledButton.icon(
              onPressed: () =>
                  ref.read(updateProvider.notifier).checkForUpdate(),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Check for Updates'),
            ),

          if (status == UpdateStatus.available && info != null) ...[
            _buildStatusRow(
              LucideIcons.download,
              'Update available: v${info.latestVersion}',
              AppColors.success,
            ),
            if (info.publishedAt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Released: ${info.publishedAt}',
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
            FilledButton.icon(
              onPressed: () =>
                  ref.read(updateProvider.notifier).downloadUpdate(),
              icon: const Icon(LucideIcons.download, size: 16),
              label: const Text('Download Update'),
            ),
          ],

          if (status == UpdateStatus.downloading) ...[
            const _SpinningStatusRow(
              label: 'Downloading update...',
              color: AppColors.richGold,
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              backgroundColor: AppColors.surfaceVariant,
              color: AppColors.richGold,
            ),
          ],

          if (status == UpdateStatus.downloaded) ...[
            _buildStatusRow(
              LucideIcons.checkCircle,
              'Update downloaded and ready to install',
              AppColors.success,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: hasActiveCompression
                  ? null
                  : () => ref.read(updateProvider.notifier).launchInstaller(),
              icon: const Icon(LucideIcons.rocket, size: 16),
              label: Text(
                hasActiveCompression
                    ? 'Waiting for compression to finish...'
                    : 'Install Update & Restart',
              ),
            ),
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
