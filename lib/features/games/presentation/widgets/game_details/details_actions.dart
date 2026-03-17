import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../../core/localization/app_localization.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';

class GameDetailsDirectStorageWarningCard extends StatelessWidget {
  const GameDetailsDirectStorageWarningCard({super.key});

  static final _warningColor = AppColors.error.withValues(alpha: 0.15);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _warningColor,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(LucideIcons.alertTriangle, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.gameDetailsDirectStorageWarning,
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
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(LucideIcons.ban, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.gameDetailsUnsupportedWarning,
                style: AppTypography.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
