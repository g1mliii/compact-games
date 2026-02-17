import 'package:flutter/material.dart';

import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../models/game_info.dart';
import 'widgets/compression_progress_indicator.dart';
import 'widgets/game_card.dart';

class ComponentTestScreen extends StatelessWidget {
  const ComponentTestScreen({super.key});

  static const int _oneGiB = 1024 * 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Component Test Screen',
            style: AppTypography.headingMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Reusable UI components from plan section 2.2.',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: const [
              SizedBox(
                width: 280,
                child: GameCard(
                  gameName: 'Cyber Quest',
                  platform: Platform.steam,
                  totalSizeBytes: 120 * _oneGiB,
                  isCompressed: false,
                ),
              ),
              SizedBox(
                width: 280,
                child: GameCard(
                  gameName: 'Racing Legends',
                  platform: Platform.epicGames,
                  totalSizeBytes: 200 * _oneGiB,
                  compressedSizeBytes: 176 * _oneGiB,
                  isCompressed: true,
                ),
              ),
              SizedBox(
                width: 280,
                child: GameCard(
                  gameName: 'Galactic Frontline',
                  platform: Platform.xboxGamePass,
                  totalSizeBytes: 80 * _oneGiB,
                  isDirectStorage: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SizedBox(
            width: 420,
            child: CompressionProgressIndicator(
              gameName: 'Racing Legends',
              filesProcessed: 2400,
              filesTotal: 6000,
              bytesSaved: 26 * _oneGiB,
              estimatedTimeRemainingSeconds: 190,
            ),
          ),
          const SizedBox(height: 20),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge.notCompressed(),
              StatusBadge.compressing(),
              StatusBadge.directStorage(),
            ],
          ),
        ],
      ),
    );
  }
}
