import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../providers/compression/compression_progress_provider.dart';
import '../../../../providers/compression/compression_provider.dart';
import 'compression_progress_indicator.dart';

const ValueKey<String> compressionInlineActivityHostKey = ValueKey<String>(
  'compressionInlineActivityHost',
);

class HomeCompressionBanner extends ConsumerWidget {
  const HomeCompressionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final activity = ref.watch(activeCompressionUiModelProvider);
    if (activity == null) {
      return const SizedBox.shrink(key: compressionInlineActivityHostKey);
    }

    return Padding(
      key: compressionInlineActivityHostKey,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: CompressionProgressIndicator(
        activity: activity,
        action: activity.canCancel
            ? CompressionActivityAction.button(
                label: l10n.commonCancel,
                onPressed: () =>
                    ref.read(compressionProvider.notifier).cancelCompression(),
              )
            : null,
      ),
    );
  }
}
