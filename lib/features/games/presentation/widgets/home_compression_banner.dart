import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/compression/compression_progress_provider.dart';
import '../../../../providers/compression/compression_provider.dart';
import 'compression_progress_indicator.dart';

class HomeCompressionBanner extends ConsumerWidget {
  const HomeCompressionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(activeCompressionProgressProvider);
    if (progress == null) return const SizedBox.shrink();

    final gameName = ref.watch(compressingGameNameProvider) ?? '';

    return Padding(
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
    );
  }
}
