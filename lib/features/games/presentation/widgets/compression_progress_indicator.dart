import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class CompressionProgressIndicator extends StatelessWidget {
  const CompressionProgressIndicator({
    required this.gameName,
    required this.filesProcessed,
    required this.filesTotal,
    required this.bytesSaved,
    this.estimatedTimeRemainingSeconds,
    this.onCancel,
    super.key,
  });

  final String gameName;
  final int filesProcessed;
  final int filesTotal;
  final int bytesSaved;
  final int? estimatedTimeRemainingSeconds;
  final VoidCallback? onCancel;

  static const LinearGradient _progressGradient = AppColors.progressGradient;

  @override
  Widget build(BuildContext context) {
    final hasKnownFileTotal = filesTotal > 0 || filesProcessed > 0;
    final effectiveFilesTotal = filesTotal < filesProcessed
        ? filesProcessed
        : filesTotal;
    final rawProgress = hasKnownFileTotal && effectiveFilesTotal > 0
        ? filesProcessed / effectiveFilesTotal
        : 0.0;
    final progress = rawProgress.clamp(0.0, 1.0).toDouble();
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.panelGradient,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildProgressBar(
              progress: progress,
              hasKnownFileTotal: hasKnownFileTotal,
            ),
            const SizedBox(height: 12),
            _buildStats(
              filesProcessed: filesProcessed,
              filesTotal: effectiveFilesTotal,
              hasKnownFileTotal: hasKnownFileTotal,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.richGold,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Compressing',
                style: AppTypography.label.copyWith(color: AppColors.richGold),
              ),
              const SizedBox(height: 2),
              Text(
                gameName,
                style: AppTypography.headingSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (onCancel != null)
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            color: AppColors.textMuted,
            onPressed: onCancel,
            tooltip: 'Cancel compression',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
      ],
    );
  }

  Widget _buildProgressBar({
    required double progress,
    required bool hasKnownFileTotal,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              hasKnownFileTotal
                  ? '${(progress * 100).toStringAsFixed(0)}%'
                  : 'Preparing...',
              style: AppTypography.mono.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.richGold,
              ),
            ),
            if (hasKnownFileTotal && estimatedTimeRemainingSeconds != null)
              Text(
                _formatTimeRemaining(estimatedTimeRemainingSeconds!),
                style: AppTypography.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: AppColors.surfaceElevated),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: _progressGradient,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStats({
    required int filesProcessed,
    required int filesTotal,
    required bool hasKnownFileTotal,
  }) {
    final savedMB = bytesSaved / (1024 * 1024);
    final savedGB = bytesSaved / (1024 * 1024 * 1024);

    if (!hasKnownFileTotal) {
      return const Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          _StatChip(icon: LucideIcons.file, label: 'Scanning files...'),
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _StatChip(
          icon: LucideIcons.file,
          label: '$filesProcessed / $filesTotal files',
        ),
        _StatChip(
          icon: LucideIcons.hardDrive,
          label: savedGB >= 1.0
              ? '${savedGB.toStringAsFixed(1)} GB saved'
              : '${savedMB.toStringAsFixed(0)} MB saved',
          color: AppColors.success,
        ),
      ],
    );
  }

  String _formatTimeRemaining(int seconds) {
    if (seconds < 60) {
      return '${seconds}s remaining';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      return '${minutes}m remaining';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '${hours}h ${minutes}m remaining';
    }
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: effectiveColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: effectiveColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
