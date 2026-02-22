import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/cover_art_utils.dart';
import '../../../core/utils/platform_icon.dart';
import '../../../models/game_info.dart';
import '../../../providers/compression/compression_provider.dart';
import '../../../providers/cover_art/cover_art_provider.dart';
import '../../../providers/games/single_game_provider.dart';
import '../../../providers/settings/settings_provider.dart';
import '../../../providers/system/platform_shell_provider.dart';

class GameDetailsScreen extends ConsumerWidget {
  const GameDetailsScreen({required this.gamePath, super.key});

  final String gamePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(singleGameProvider(gamePath));
    if (game == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Game Details')),
        body: const Center(
          child: Text('Game not found.', style: AppTypography.bodyMedium),
        ),
      );
    }

    final coverResult = ref.watch(coverArtProvider(game.path)).valueOrNull;
    final coverProvider = imageProviderFromCover(coverResult);
    final isExcluded = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.excludedPaths.contains(game.path) ??
            false,
      ),
    );
    final currentSize = game.compressedSize ?? game.sizeBytes;
    final savedBytes = (game.sizeBytes - currentSize).clamp(0, game.sizeBytes);
    final savingsPercent = (game.savingsRatio * 100).toStringAsFixed(1);
    final lastPlayedText = _formatLastPlayed(game.lastPlayed);
    final windowWidth = MediaQuery.sizeOf(context).width;
    final maxCoverWidth = windowWidth < 1100 ? 220.0 : 250.0;
    final deferred = Scrollable.recommendDeferredLoadingForContext(context);
    final filterQuality = deferred ? FilterQuality.none : FilterQuality.low;

    return Scaffold(
      appBar: AppBar(
        title: Text(game.name),
        actions: [
          IconButton(
            tooltip: 'Open folder',
            onPressed: () =>
                ref.read(platformShellServiceProvider).openFolder(game.path),
            icon: const Icon(LucideIcons.folderOpen),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxCoverWidth),
              child: RepaintBoundary(
                child: AspectRatio(
                  aspectRatio: AppConstants.coverAspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ColoredBox(
                      color: AppColors.surfaceElevated,
                      child: coverProvider == null
                          ? _CoverFallback(platform: game.platform)
                          : Image(
                              image: ResizeImage(
                                coverProvider,
                                width: _coverDecodeWidth(
                                  context: context,
                                  logicalWidth: maxCoverWidth,
                                ),
                              ),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              alignment: Alignment.center,
                              filterQuality: filterQuality,
                              isAntiAlias: true,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  _CoverFallback(platform: game.platform),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatLine(
                    label: 'Platform',
                    value: game.platform.displayName,
                  ),
                  _StatLine(
                    label: 'Compression',
                    value: game.isCompressed ? 'Compressed' : 'Not compressed',
                  ),
                  _StatLine(
                    label: 'DirectStorage',
                    value: game.isDirectStorage ? 'Detected' : 'Not detected',
                  ),
                  _StatLine(
                    label: 'Auto-compress',
                    value: isExcluded ? 'Excluded' : 'Included',
                  ),
                  _StatLine(
                    label: 'Original size',
                    value: _formatBytes(game.sizeBytes),
                  ),
                  _StatLine(
                    label: 'Current size',
                    value: _formatBytes(currentSize),
                  ),
                  _StatLine(
                    label: 'Space saved',
                    value: _formatBytes(savedBytes),
                  ),
                  _StatLine(label: 'Savings', value: '$savingsPercent%'),
                  _StatLine(label: 'Last played', value: lastPlayedText),
                  const SizedBox(height: 6),
                  SelectableText(
                    game.path,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (game.isDirectStorage) ...[
            const SizedBox(height: 12),
            Card(
              color: AppColors.error.withValues(alpha: 0.15),
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
            ),
          ],
          const SizedBox(height: 16),
          _ActionButtons(game: game),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(2)} GB';
  }

  String _formatLastPlayed(DateTime? value) {
    if (value == null) {
      return 'Unknown';
    }
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  int _coverDecodeWidth({
    required BuildContext context,
    required double logicalWidth,
  }) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final raw = (logicalWidth * dpr).clamp(224.0, 448.0);
    return ((raw / 64).round() * 64).clamp(192, 448).toInt();
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.game});

  final GameInfo game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExcluded = ref.watch(
      settingsProvider.select(
        (async) =>
            async.valueOrNull?.settings.excludedPaths.contains(game.path) ??
            false,
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!game.isCompressed)
              FilledButton.icon(
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
            else
              FilledButton.icon(
                onPressed: () => ref
                    .read(compressionProvider.notifier)
                    .startDecompression(
                      gamePath: game.path,
                      gameName: game.name,
                    ),
                icon: const Icon(LucideIcons.unplug),
                label: const Text('Decompress'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
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
          ],
        ),
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: AppTypography.bodySmall),
          ),
          Expanded(child: Text(value, style: AppTypography.bodyMedium)),
        ],
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.platform});

  final Platform platform;

  @override
  Widget build(BuildContext context) {
    final icon = platformIcon(platform);
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(child: Icon(icon, size: 48, color: AppColors.desertSand)),
    );
  }
}
