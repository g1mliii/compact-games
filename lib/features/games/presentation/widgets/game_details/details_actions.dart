import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../models/game_info.dart';
import '../../../../../providers/compression/compression_provider.dart';
import '../../../../../providers/settings/settings_provider.dart';

class GameDetailsActionsCard extends ConsumerWidget {
  const GameDetailsActionsCard({
    required this.game,
    required this.centered,
    required this.isExcluded,
    super.key,
  });

  final GameInfo game;
  final bool centered;
  final bool isExcluded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alignment = centered ? Alignment.center : Alignment.centerLeft;
    final buttonWidth = centered ? 360.0 : 380.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: alignment,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: buttonWidth),
                child: !game.isCompressed
                    ? FilledButton.icon(
                        onPressed: game.isDirectStorage
                            ? null
                            : () => ref
                                  .read(compressionProvider.notifier)
                                  .startCompression(
                                    gamePath: game.path,
                                    gameName: game.name,
                                  ),
                        icon: const Icon(LucideIcons.archive),
                        label: const Text('Compress Now'),
                      )
                    : FilledButton.icon(
                        onPressed: () => ref
                            .read(compressionProvider.notifier)
                            .startDecompression(
                              gamePath: game.path,
                              gameName: game.name,
                            ),
                        icon: const Icon(LucideIcons.archiveRestore),
                        label: const Text('Decompress'),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: alignment,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: buttonWidth),
                child: OutlinedButton.icon(
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .toggleGameExclusion(game.path),
                  icon: const Icon(LucideIcons.shieldAlert),
                  label: Text(
                    isExcluded
                        ? 'Include In Auto-Compression'
                        : 'Exclude From Auto-Compression',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
