import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/film_grain_overlay.dart';

class GameGridEmptyView extends StatelessWidget {
  const GameGridEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.panelGradient,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                child: FilmGrainOverlay(opacity: 0.02, density: 0.1),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.gamepad2,
                  size: 48,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 16),
                const Text('No games found', style: AppTypography.headingSmall),
                const SizedBox(height: 8),
                Text(
                  'Games from Steam, Epic, GOG, and other launchers\nwill appear here automatically.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GameGridErrorView extends StatelessWidget {
  const GameGridErrorView({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.panelGradient,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                child: FilmGrainOverlay(opacity: 0.02, density: 0.1),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.alertCircle,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load games',
                  style: AppTypography.headingSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
