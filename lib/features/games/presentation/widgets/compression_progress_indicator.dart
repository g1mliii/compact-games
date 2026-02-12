import 'package:flutter/material.dart';
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

  static const LinearGradient _progressGradient = LinearGradient(
    colors: [AppColors.compressing, Color(0xFF4A93E6)],
  );

  @override
  Widget build(BuildContext context) {
    final progress = filesTotal > 0 ? filesProcessed / filesTotal : 0.0;
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildProgressBar(progress),
            const SizedBox(height: 12),
            _buildStats(),
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
            color: AppColors.compressing,
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
                style: AppTypography.label.copyWith(
                  color: AppColors.compressing,
                ),
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
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.textMuted,
            onPressed: onCancel,
            tooltip: 'Cancel compression',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
      ],
    );
  }

  Widget _buildProgressBar(double progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: AppTypography.mono.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.compressing,
              ),
            ),
            if (estimatedTimeRemainingSeconds != null)
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

  Widget _buildStats() {
    final savedMB = bytesSaved / (1024 * 1024);
    final savedGB = bytesSaved / (1024 * 1024 * 1024);

    return Row(
      children: [
        _StatChip(
          icon: Icons.description_outlined,
          label: '$filesProcessed / $filesTotal files',
        ),
        const SizedBox(width: 12),
        _StatChip(
          icon: Icons.storage_outlined,
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
