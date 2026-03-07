import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_typography.dart';
import '../theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    required this.color,
    this.icon,
    this.variant = StatusBadgeVariant.filled,
    this.toneAlpha = 1.0,
    super.key,
  });

  factory StatusBadge.compressed(double savedGB) {
    return StatusBadge(
      label: 'Saved ${savedGB.toStringAsFixed(1)} GB',
      color: AppColors.compressed,
      icon: LucideIcons.checkCircle2,
    );
  }

  const StatusBadge.notCompressed({super.key})
    : label = 'Not Compressed',
      color = AppColors.notCompressed,
      icon = LucideIcons.circle,
      variant = StatusBadgeVariant.filled,
      toneAlpha = 0.78;

  const StatusBadge.directStorage({super.key})
    : label = 'DirectStorage',
      color = AppColors.directStorage,
      icon = LucideIcons.alertTriangle,
      variant = StatusBadgeVariant.filled,
      toneAlpha = 1.0;

  const StatusBadge.unsupported({super.key})
    : label = 'Unsupported',
      color = AppColors.warning,
      icon = LucideIcons.ban,
      variant = StatusBadgeVariant.filled,
      toneAlpha = 1.0;

  const StatusBadge.compressing({super.key})
    : label = 'Compressing',
      color = AppColors.compressing,
      icon = LucideIcons.hourglass,
      variant = StatusBadgeVariant.filled,
      toneAlpha = 1.0;

  final String label;
  final Color color;
  final IconData? icon;
  final StatusBadgeVariant variant;
  final double toneAlpha;

  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(8),
  );
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 4,
  );

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color.withValues(alpha: toneAlpha);
    final backgroundColor = effectiveColor.withValues(alpha: 0.1);
    final borderColor = effectiveColor.withValues(alpha: 0.3);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: variant == StatusBadgeVariant.filled
            ? backgroundColor
            : Colors.transparent,
        borderRadius: _borderRadius,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: _padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: effectiveColor),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTypography.label.copyWith(
                color: effectiveColor,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum StatusBadgeVariant { filled, outlined }
