import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../providers/system/auto_compression_status_provider.dart';

const ValueKey<String> _watcherStatusBannerKey = ValueKey<String>(
  'settingsWatcherStatusBanner',
);

class WatcherStatusBanner extends ConsumerWidget {
  const WatcherStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final watcherActive = ref.watch(
      autoCompressionRunningProvider.select(
        (value) => value.valueOrNull ?? false,
      ),
    );
    final label = watcherActive
        ? l10n.settingsWatcherStatusActive
        : l10n.settingsWatcherStatusPaused;
    final color = watcherActive ? AppColors.success : AppColors.warning;
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusBadge(
        key: _watcherStatusBannerKey,
        label: label,
        color: color,
        showIcon: false,
        variant: StatusBadgeVariant.outlined,
        toneAlpha: 0.9,
      ),
    );
  }
}
