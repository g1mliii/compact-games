import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/compression/compression_progress_provider.dart';
import 'compression_progress_indicator.dart';

const ValueKey<String> compressionFloatingActivityHostKey = ValueKey<String>(
  'compressionFloatingActivityHost',
);

class CompressionActivityOverlay extends ConsumerWidget {
  const CompressionActivityOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shouldShow = ref.watch(showFloatingActivityOverlayProvider);
    if (!shouldShow) {
      return const SizedBox.shrink(key: compressionFloatingActivityHostKey);
    }
    final activity = ref.watch(activeCompressionUiModelProvider);
    final activeRunId = ref.watch(activeCompressionRunIdProvider);
    if (activity == null) {
      return const SizedBox.shrink(key: compressionFloatingActivityHostKey);
    }

    // Placed after early-returns to avoid subscribing to MediaQuery when
    // the overlay is hidden, preventing unnecessary rebuilds on resize.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final narrow = screenWidth < 920;
    final maxWidth = narrow
        ? (screenWidth - 32).clamp(260.0, 420.0).toDouble()
        : 360.0;

    return Align(
      alignment: narrow ? Alignment.topCenter : Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: CompressionProgressIndicator(
            key: compressionFloatingActivityHostKey,
            activity: activity,
            compact: true,
            action: CompressionActivityAction.icon(
              label: 'Dismiss monitor',
              onPressed: () {
                ref
                        .read(
                          dismissedFloatingActivityRunIdProvider.notifier,
                        )
                        .state =
                    activeRunId;
              },
            ),
          ),
        ),
      ),
    );
  }
}
