import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/status_badge.dart';

const double _statusActionHeight = 40;
const ValueKey<String> _inventoryStatusPanelKey = ValueKey<String>(
  'inventoryStatusPanel',
);
const ValueKey<String> _inventoryWatcherToggleButtonKey = ValueKey<String>(
  'inventoryWatcherToggleButton',
);
const ValueKey<String> _inventoryAdvancedScanToggleButtonKey = ValueKey<String>(
  'inventoryAdvancedScanToggleButton',
);
const ValueKey<String> _inventoryFullRescanButtonKey = ValueKey<String>(
  'inventoryFullRescanButton',
);
const ValueKey<String> _inventoryAlgorithmBadgeKey = ValueKey<String>(
  'inventoryAlgorithmBadge',
);
const ValueKey<String> _inventoryWatcherBadgeKey = ValueKey<String>(
  'inventoryWatcherBadge',
);

class InventoryStatusRow extends StatelessWidget {
  const InventoryStatusRow({
    super.key,
    required this.algorithmLabel,
    required this.watcherActive,
    required this.watcherEnabled,
    required this.advancedEnabled,
    required this.onWatcherEnabledChanged,
    required this.onAdvancedChanged,
    required this.onRunFullRescan,
    this.canRunFullRescan = true,
  });

  final String algorithmLabel;
  final bool watcherActive;
  final bool watcherEnabled;
  final bool advancedEnabled;
  final ValueChanged<bool> onWatcherEnabledChanged;
  final ValueChanged<bool> onAdvancedChanged;
  final VoidCallback onRunFullRescan;
  final bool canRunFullRescan;

  static final _panelDecoration = BoxDecoration(
    color: AppColors.surface.withValues(alpha: 0.58),
    borderRadius: const BorderRadius.all(Radius.circular(12)),
    border: Border.all(color: AppColors.borderSubtle),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RepaintBoundary(
      child: Container(
        key: _inventoryStatusPanelKey,
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: _panelDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InventoryInfoBadge(
                  badgeKey: _inventoryAlgorithmBadgeKey,
                  icon: LucideIcons.cpu,
                  label: l10n.inventoryAlgorithmBadgeLabel,
                  value: algorithmLabel,
                ),
                _InventoryInfoBadge(
                  badgeKey: _inventoryWatcherBadgeKey,
                  icon: watcherActive
                      ? LucideIcons.radioTower
                      : LucideIcons.pauseCircle,
                  label: l10n.inventoryWatcherBadgeLabel,
                  value: watcherActive
                      ? l10n.inventoryWatcherBadgeActive
                      : l10n.inventoryWatcherBadgePaused,
                  color: watcherActive ? AppColors.success : AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: _inventoryWatcherToggleButtonKey,
                  style: _watcherActionStyle(context, watcherActive),
                  onPressed: () => onWatcherEnabledChanged(!watcherEnabled),
                  icon: Icon(
                    watcherEnabled ? LucideIcons.pause : LucideIcons.play,
                    size: 16,
                  ),
                  label: Text(
                    watcherEnabled
                        ? l10n.inventoryPauseWatcher
                        : l10n.inventoryResumeWatcher,
                  ),
                ),
                OutlinedButton.icon(
                  key: _inventoryAdvancedScanToggleButtonKey,
                  onPressed: () => onAdvancedChanged(!advancedEnabled),
                  icon: Icon(
                    advancedEnabled
                        ? LucideIcons.toggleRight
                        : LucideIcons.scan,
                    size: 16,
                  ),
                  label: Text(
                    advancedEnabled
                        ? l10n.inventoryAdvancedMetadataScanOn
                        : l10n.inventoryAdvancedMetadataScanOff,
                  ),
                ),
              ],
            ),
            if (advancedEnabled) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: _statusActionHeight,
                child: FilledButton.icon(
                  key: _inventoryFullRescanButtonKey,
                  onPressed: canRunFullRescan ? onRunFullRescan : null,
                  icon: const Icon(LucideIcons.scan, size: 16),
                  label: Text(
                    canRunFullRescan
                        ? l10n.inventoryRunFullRescan
                        : l10n.inventoryRescanUnavailableWhileLoading,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static ButtonStyle _watcherActionStyle(
    BuildContext context,
    bool watcherActive,
  ) {
    final base =
        Theme.of(context).outlinedButtonTheme.style ?? const ButtonStyle();
    if (!watcherActive) {
      return base;
    }

    return base.copyWith(
      backgroundColor: WidgetStatePropertyAll(
        AppColors.richGold.withValues(alpha: 0.08),
      ),
      side: WidgetStatePropertyAll(
        BorderSide(
          color: AppColors.richGold.withValues(alpha: 0.85),
          width: 1.6,
        ),
      ),
    );
  }
}

class _InventoryInfoBadge extends StatelessWidget {
  const _InventoryInfoBadge({
    required this.badgeKey,
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.info,
  });

  final Key badgeKey;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      key: badgeKey,
      icon: icon,
      label: '$label: $value',
      color: color,
    );
  }
}
