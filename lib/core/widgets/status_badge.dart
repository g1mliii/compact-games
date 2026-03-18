import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_typography.dart';
import '../theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    required this.color,
    this.icon,
    this.showIcon = true,
    this.variant = StatusBadgeVariant.filled,
    this.toneAlpha = 1.0,
    super.key,
  });

  static const BoxShadow _kShadow = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.16),
    blurRadius: 10,
    offset: Offset(0, 4),
  );

  // Keyed by Object.hash(color.value, variantIndex, toneAlphaBits).
  static final Map<int, BoxDecoration> _decorationCache = {};
  static final Map<int, BoxDecoration> _iconDecorationCache = {};

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
      showIcon = true,
      variant = StatusBadgeVariant.filled,
      toneAlpha = 0.78;

  const StatusBadge.directStorage({super.key})
    : label = 'DirectStorage',
      color = AppColors.directStorage,
      icon = LucideIcons.alertTriangle,
      showIcon = true,
      variant = StatusBadgeVariant.filled,
      toneAlpha = 1.0;

  const StatusBadge.unsupported({super.key})
    : label = 'Unsupported',
      color = AppColors.warning,
      icon = LucideIcons.ban,
      showIcon = true,
      variant = StatusBadgeVariant.filled,
      toneAlpha = 1.0;

  const StatusBadge.compressing({super.key})
    : label = 'Compressing',
      color = AppColors.compressing,
      icon = LucideIcons.hourglass,
      showIcon = true,
      variant = StatusBadgeVariant.filled,
      toneAlpha = 1.0;

  final String label;
  final Color color;
  final IconData? icon;
  final bool showIcon;
  final StatusBadgeVariant variant;
  final double toneAlpha;

  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(12),
  );
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 5,
  );

  BoxDecoration _buildDecoration() {
    final effectiveColor = color.withValues(alpha: toneAlpha);
    final borderColor = Color.lerp(
      AppColors.borderSubtle,
      effectiveColor.withValues(alpha: 0.4),
      0.72,
    )!;
    if (variant == StatusBadgeVariant.outlined) {
      return BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.28),
        borderRadius: _borderRadius,
        border: Border.all(color: borderColor),
        boxShadow: const [_kShadow],
      );
    }
    final topColor = Color.lerp(
      AppColors.surfaceCard,
      effectiveColor.withValues(alpha: 0.12),
      0.24,
    )!;
    final bottomColor = Color.lerp(
      AppColors.surface,
      effectiveColor.withValues(alpha: 0.18),
      0.34,
    )!;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [topColor, bottomColor],
      ),
      borderRadius: _borderRadius,
      border: Border.all(color: borderColor),
      boxShadow: const [_kShadow],
    );
  }

  BoxDecoration _buildIconDecoration() {
    final effectiveColor = color.withValues(alpha: toneAlpha);
    return BoxDecoration(
      color: effectiveColor.withValues(alpha: 0.14),
      borderRadius: const BorderRadius.all(Radius.circular(5)),
      border: Border.all(color: effectiveColor.withValues(alpha: 0.24)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color.withValues(alpha: toneAlpha);
    final labelColor = Color.lerp(AppColors.textPrimary, effectiveColor, 0.34)!;

    final cacheKey = Object.hash(
      color.toARGB32(),
      variant.index,
      toneAlpha.hashCode,
    );

    final decoration = _decorationCache.putIfAbsent(cacheKey, _buildDecoration);

    return DecoratedBox(
      decoration: decoration,
      child: Padding(
        padding: _padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIcon) ...[
              SizedBox(
                width: 18,
                height: 18,
                child: DecoratedBox(
                  decoration: _iconDecorationCache.putIfAbsent(
                    Object.hash(
                      color.toARGB32(),
                      toneAlpha.hashCode,
                      0x69636f6e,
                    ),
                    _buildIconDecoration,
                  ),
                  child: Center(
                    child: icon != null
                        ? Icon(icon, size: 11, color: effectiveColor)
                        : SizedBox(
                            width: 5,
                            height: 5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: effectiveColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppTypography.label.copyWith(
                color: labelColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum StatusBadgeVariant { filled, outlined }
