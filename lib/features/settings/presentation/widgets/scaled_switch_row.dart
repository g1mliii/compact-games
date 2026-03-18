import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';

class ScaledSwitchRow extends StatelessWidget {
  const ScaledSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enableLabelSurfaceHover = true,
    this.showLabelSurfaceDecoration = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enableLabelSurfaceHover;
  final bool showLabelSurfaceDecoration;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: Ink(
                  decoration: BoxDecoration(
                    color: showLabelSurfaceDecoration && value
                        ? AppColors.selectionSurface
                        : Colors.transparent,
                    borderRadius: _radius,
                    border: Border.all(
                      color: showLabelSurfaceDecoration && value
                          ? AppColors.selectionBorder
                          : Colors.transparent,
                    ),
                  ),
                  child: InkWell(
                    onTap: () => onChanged(!value),
                    borderRadius: _radius,
                    overlayColor: enableLabelSurfaceHover
                        ? appFocusInteractionOverlay
                        : const WidgetStatePropertyAll(Colors.transparent),
                    hoverColor: enableLabelSurfaceHover
                        ? AppColors.selectionSurface.withValues(
                            alpha: value ? 0.24 : 0.1,
                          )
                        : Colors.transparent,
                    focusColor: enableLabelSurfaceHover
                        ? AppColors.selectionSurface.withValues(
                            alpha: value ? 0.2 : 0.08,
                          )
                        : Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 36),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(label, style: AppTypography.bodyMedium),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 52, minHeight: 36),
              child: Align(
                alignment: Alignment.center,
                child: Switch(value: value, onChanged: onChanged),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
