import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../providers/compression/compression_progress_provider.dart';
import 'compression_progress_indicator.dart';

const ValueKey<String> compressionFloatingActivityHostKey = ValueKey<String>(
  'compressionFloatingActivityHost',
);

class CompressionActivityOverlay extends ConsumerWidget {
  const CompressionActivityOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final shouldShow = ref.watch(showFloatingActivityOverlayProvider);
    if (!shouldShow) {
      return const SizedBox.shrink(key: compressionFloatingActivityHostKey);
    }
    final activity = ref.watch(activeCompressionUiModelProvider);
    final activeRunId = ref.watch(activeCompressionRunIdProvider);
    if (activity == null) {
      return const SizedBox.shrink(key: compressionFloatingActivityHostKey);
    }

    // Use LayoutBuilder instead of MediaQuery.sizeOf so that this widget only
    // rebuilds when the overlay's own allocated width bucket changes, not on
    // every window resize event for the whole app.
    return LayoutBuilder(
      builder: (context, constraints) {
        final overlayWidth = constraints.maxWidth;
        final narrow = overlayWidth < 920;
        final maxWidth = narrow
            ? (overlayWidth - 32).clamp(260.0, 420.0).toDouble()
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
                  label: l10n.activityDismissMonitor,
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
      },
    );
  }
}
