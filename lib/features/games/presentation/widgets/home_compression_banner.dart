import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/compression/compression_progress_provider.dart';
import '../../../../providers/compression/compression_provider.dart';
import '../../../../providers/compression/compression_state.dart';
import 'compression_progress_indicator.dart';

class HomeCompressionBanner extends ConsumerWidget {
  const HomeCompressionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeJob = ref.watch(activeCompressionJobProvider);
    final progress = ref.watch(activeCompressionProgressProvider);
    final gameName = ref.watch(compressingGameNameProvider) ?? '';
    return switch (activeJob?.type) {
      CompressionJobType.compression when progress != null => Padding(
        key: const ValueKey<String>('compression-active'),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: CompressionProgressIndicator(
          gameName: gameName,
          filesProcessed: progress.filesProcessed,
          filesTotal: progress.filesTotal,
          bytesSaved: progress.bytesSaved,
          estimatedTimeRemainingSeconds:
              progress.estimatedTimeRemaining?.inSeconds,
          onCancel: () =>
              ref.read(compressionProvider.notifier).cancelCompression(),
        ),
      ),
      CompressionJobType.decompression => Padding(
        key: const ValueKey<String>('decompression-active'),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: _DecompressionIndicator(gameName: gameName),
      ),
      _ => const SizedBox.shrink(key: ValueKey<String>('compression-empty')),
    };
  }
}

class _DecompressionIndicator extends StatelessWidget {
  const _DecompressionIndicator({required this.gameName});

  final String gameName;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.panelGradient,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Decompressing',
                    style: AppTypography.label.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    gameName,
                    style: AppTypography.headingSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.refreshCcw,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
