import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/system/auto_compression_status_provider.dart';

const ValueKey<String> _watcherStatusBannerKey = ValueKey<String>(
  'settingsWatcherStatusBanner',
);

class WatcherStatusBanner extends ConsumerWidget {
  const WatcherStatusBanner({super.key});

  static const _kBorderRadius = BorderRadius.all(Radius.circular(10));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final watcherActive = ref.watch(
      autoCompressionRunningProvider.select(
        (value) => value.valueOrNull ?? false,
      ),
    );
    return DecoratedBox(
      key: _watcherStatusBannerKey,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: _kBorderRadius,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            watcherActive
                ? l10n.settingsWatcherStatusActive
                : l10n.settingsWatcherStatusPaused,
            style: AppTypography.bodySmall.copyWith(
              color: watcherActive ? AppColors.success : AppColors.warning,
            ),
          ),
        ),
      ),
    );
  }
}
