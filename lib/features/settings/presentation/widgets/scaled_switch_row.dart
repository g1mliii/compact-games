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
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: value ? AppColors.selectionSurface : Colors.transparent,
            borderRadius: _radius,
            border: Border.all(
              color: value ? AppColors.selectionBorder : Colors.transparent,
            ),
          ),
          child: InkWell(
            onTap: () => onChanged(!value),
            borderRadius: _radius,
            overlayColor: appFocusInteractionOverlay,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: AppTypography.bodyMedium),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 52,
                      minHeight: appDesktopControlMin,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Switch(value: value, onChanged: onChanged),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
