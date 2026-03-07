import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';

class GameDetailsDirectStorageWarningCard extends StatelessWidget {
  const GameDetailsDirectStorageWarningCard({super.key});

  static final _warningColor = AppColors.error.withValues(alpha: 0.15);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _warningColor,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(LucideIcons.alertTriangle, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'DirectStorage detected. Compression can impact runtime performance.',
                style: AppTypography.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameDetailsUnsupportedWarningCard extends StatelessWidget {
  const GameDetailsUnsupportedWarningCard({super.key});

  static final _warningColor = AppColors.warning.withValues(alpha: 0.15);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _warningColor,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(LucideIcons.ban, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'This game is known to have issues after WOF compression.',
                style: AppTypography.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
