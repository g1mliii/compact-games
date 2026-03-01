import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/system/auto_compression_status_provider.dart';

class WatcherStatusBanner extends ConsumerWidget {
  const WatcherStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watcherActive = ref.watch(
      autoCompressionRunningProvider.select(
        (value) => value.valueOrNull ?? false,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            watcherActive ? 'Watcher status: active' : 'Watcher status: paused',
            style: AppTypography.bodySmall.copyWith(
              color: watcherActive ? AppColors.success : AppColors.warning,
            ),
          ),
        ),
      ),
    );
  }
}
