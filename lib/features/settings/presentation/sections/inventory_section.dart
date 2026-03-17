import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../widgets/scaled_switch_row.dart';
import '../widgets/settings_section_card.dart';
import '../widgets/watcher_status_banner.dart';

const ValueKey<String> _watcherToggleButtonKey = ValueKey<String>(
  'settingsWatcherToggleButton',
);
const ValueKey<String> _advancedToggleKey = ValueKey<String>(
  'settingsInventoryAdvancedToggle',
);

class InventorySection extends ConsumerWidget {
  const InventorySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final autoCompress = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.settings.autoCompress),
    );
    final advancedScan = ref.watch(
      settingsProvider.select(
        (s) => s.valueOrNull?.settings.inventoryAdvancedScanEnabled,
      ),
    );
    if (autoCompress == null || advancedScan == null) {
      return const SizedBox.shrink();
    }

    return SettingsSectionCard(
      icon: LucideIcons.slidersHorizontal,
      title: l10n.settingsInventorySectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WatcherStatusBanner(),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
              child: SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  key: _watcherToggleButtonKey,
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .setAutoCompress(!autoCompress),
                  icon: Icon(
                    autoCompress ? LucideIcons.pause : LucideIcons.play,
                    size: 16,
                  ),
                  label: Text(
                    autoCompress
                        ? l10n.settingsPauseWatcher
                        : l10n.settingsResumeWatcher,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(
              autoCompress
                  ? l10n.settingsWatcherAutomationEnabled
                  : l10n.settingsWatcherAutomationDisabled,
              style: AppTypography.bodySmall,
            ),
          ),
          ScaledSwitchRow(
            key: _advancedToggleKey,
            label: l10n.settingsEnableFullMetadataInventoryScan,
            value: advancedScan,
            onChanged: (enabled) => ref
                .read(settingsProvider.notifier)
                .setInventoryAdvancedScanEnabled(enabled),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(
              l10n.settingsInventoryAdvancedDescription,
              style: AppTypography.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 2),
            child: Text(
              l10n.settingsSteamGridDbManagedOnce,
              style: AppTypography.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
