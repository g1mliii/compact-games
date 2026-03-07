import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/compression/compression_progress_provider.dart';

enum CompressionActivityActionStyle { icon, button }

class CompressionActivityAction {
  const CompressionActivityAction.icon({
    required this.label,
    required this.onPressed,
    this.icon = LucideIcons.x,
  }) : style = CompressionActivityActionStyle.icon;

  const CompressionActivityAction.button({
    required this.label,
    required this.onPressed,
    this.icon,
  }) : style = CompressionActivityActionStyle.button;

  final CompressionActivityActionStyle style;
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
}

class CompressionProgressIndicator extends StatelessWidget {
  const CompressionProgressIndicator({
    required this.activity,
    this.compact = false,
    this.action,
    super.key,
  });

  final CompressionActivityUiModel activity;
  final bool compact;
  final CompressionActivityAction? action;

  static const LinearGradient _compressionGradient = AppColors.progressGradient;
  static const LinearGradient _decompressionGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.info, AppColors.success],
  );
  static const BorderRadius _cardRadius = BorderRadius.all(Radius.circular(12));
  static final BoxDecoration _cardDecoration = BoxDecoration(
    gradient: AppColors.panelGradient,
    borderRadius: _cardRadius,
    border: Border.all(color: AppColors.border),
  );

  @override
  Widget build(BuildContext context) {
    final accentColor = activity.isCompression
        ? AppColors.richGold
        : AppColors.success;
    final progress = activity.hasKnownFileTotal
        ? (activity.percent / 100).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return RepaintBoundary(
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: DecoratedBox(
          decoration: _cardDecoration,
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActivityHeader(
                  activity: activity,
                  compact: compact,
                  accentColor: accentColor,
                  action: action,
                ),
                SizedBox(height: compact ? 10 : 12),
                _ActivityProgressBar(
                  activity: activity,
                  compact: compact,
                  progress: progress,
                  accentColor: accentColor,
                  gradient: activity.isCompression
                      ? _compressionGradient
                      : _decompressionGradient,
                ),
                SizedBox(height: compact ? 10 : 12),
                _ActivityStats(activity: activity, compact: compact),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({
    required this.activity,
    required this.compact,
    required this.accentColor,
    required this.action,
  });

  final CompressionActivityUiModel activity;
  final bool compact;
  final Color accentColor;
  final CompressionActivityAction? action;

  @override
  Widget build(BuildContext context) {
    final titleStyle = compact
        ? AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700)
        : AppTypography.headingSmall;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ActivityLeadingIcon(
          compact: compact,
          accentColor: accentColor,
          icon: activity.isCompression
              ? LucideIcons.archive
              : LucideIcons.archiveRestore,
        ),
        SizedBox(width: compact ? 10 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                activity.statusLabel,
                style: AppTypography.label.copyWith(color: accentColor),
              ),
              const SizedBox(height: 2),
              Text(
                activity.gameName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ],
          ),
        ),
        if (action != null)
          _ActivityHeaderAction(action: action!, compact: compact),
      ],
    );
  }
}

class _ActivityHeaderAction extends StatelessWidget {
  const _ActivityHeaderAction({required this.action, required this.compact});

  final CompressionActivityAction action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    switch (action.style) {
      case CompressionActivityActionStyle.icon:
        return Semantics(
          button: true,
          label: action.label,
          child: IconButton(
            icon: Icon(action.icon ?? LucideIcons.x, size: 18),
            color: AppColors.textMuted,
            onPressed: action.onPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: compact
                ? VisualDensity.compact
                : VisualDensity.standard,
          ),
        );
      case CompressionActivityActionStyle.button:
        return TextButton(
          onPressed: action.onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textMuted,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 6 : 8,
            ),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: compact
                ? VisualDensity.compact
                : VisualDensity.standard,
          ),
          child: Text(
            action.label,
            style: AppTypography.label.copyWith(color: AppColors.textMuted),
          ),
        );
    }
  }
}

class _ActivityLeadingIcon extends StatelessWidget {
  const _ActivityLeadingIcon({
    required this.compact,
    required this.accentColor,
    required this.icon,
  });

  final bool compact;
  final Color accentColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 12.0 : 14.0;
    final containerSize = compact ? 24.0 : 28.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: SizedBox(
        width: containerSize,
        height: containerSize,
        child: Center(
          child: Icon(icon, size: iconSize, color: accentColor),
        ),
      ),
    );
  }
}

class _ActivityProgressBar extends StatelessWidget {
  const _ActivityProgressBar({
    required this.activity,
    required this.compact,
    required this.progress,
    required this.accentColor,
    required this.gradient,
  });

  final CompressionActivityUiModel activity;
  final bool compact;
  final double progress;
  final Color accentColor;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final trailingText =
        activity.hasKnownFileTotal && activity.etaSeconds != null
        ? _formatTimeRemaining(activity.etaSeconds!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                activity.hasKnownFileTotal
                    ? '${activity.percent}%'
                    : 'Preparing...',
                style: AppTypography.monoMedium.copyWith(color: accentColor),
              ),
            ),
            if (trailingText != null)
              Text(trailingText, style: AppTypography.bodySmall),
          ],
        ),
        SizedBox(height: compact ? 6 : 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            height: compact ? 7 : 8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppColors.surfaceElevated),
                if (activity.hasKnownFileTotal)
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: gradient),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityStats extends StatelessWidget {
  const _ActivityStats({required this.activity, required this.compact});

  final CompressionActivityUiModel activity;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final spacing = compact ? 10.0 : 12.0;
    final runSpacing = compact ? 4.0 : 6.0;

    if (!activity.hasKnownFileTotal) {
      return Row(
        children: [
          const Icon(
            LucideIcons.file,
            size: 14,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              activity.isCompression
                  ? 'Scanning files...'
                  : 'Scanning compressed files...',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: [
        _StatChip(icon: LucideIcons.file, label: _formatFileProgress(activity)),
        _StatChip(
          icon: LucideIcons.hardDrive,
          label: _formatBytesDelta(activity),
          color: activity.isCompression ? AppColors.success : AppColors.info,
        ),
      ],
    );
  }

  String _formatBytesDelta(CompressionActivityUiModel activity) {
    final deltaBytes = activity.bytesDelta;
    final deltaGiB = deltaBytes / (1024 * 1024 * 1024);
    final deltaMiB = deltaBytes / (1024 * 1024);
    final amountText = deltaGiB >= 1.0
        ? '${deltaGiB.toStringAsFixed(1)} GB'
        : '${deltaMiB.toStringAsFixed(0)} MB';

    return activity.isCompression
        ? '$amountText saved'
        : '$amountText restoring';
  }

  String _formatFileProgress(CompressionActivityUiModel activity) {
    final countLabel =
        '${activity.filesProcessed} / ${activity.filesTotal} files';
    if (!activity.isFileCountApproximate) {
      return countLabel;
    }
    return '~$countLabel';
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
        Text(label, style: AppTypography.label.copyWith(color: effectiveColor)),
      ],
    );
  }
}

String _formatTimeRemaining(int seconds) {
  if (seconds < 60) {
    return '${seconds}s remaining';
  }
  if (seconds < 3600) {
    final minutes = seconds ~/ 60;
    return '${minutes}m remaining';
  }

  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  return '${hours}h ${minutes}m remaining';
}
