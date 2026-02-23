import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

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
    final watcherLabel = watcherActive ? 'Watcher active' : 'Watcher paused';
    return Container(
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
                icon: LucideIcons.cpu,
                label: 'Algorithm',
                value: algorithmLabel,
              ),
              _InventoryInfoBadge(
                icon: watcherActive
                    ? LucideIcons.radioTower
                    : LucideIcons.pauseCircle,
                label: 'Watcher',
                value: watcherActive ? 'Active' : 'Paused',
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
                onPressed: () => onWatcherEnabledChanged(!watcherEnabled),
                icon: Icon(
                  watcherEnabled ? LucideIcons.pause : LucideIcons.play,
                  size: 16,
                ),
                label: Text(
                  watcherEnabled ? 'Pause watcher' : 'Resume watcher',
                ),
              ),
              FilledButton.tonalIcon(
                key: _inventoryAdvancedScanToggleButtonKey,
                onPressed: () => onAdvancedChanged(!advancedEnabled),
                icon: Icon(
                  advancedEnabled ? LucideIcons.toggleRight : LucideIcons.scan,
                  size: 16,
                ),
                label: Text(
                  advancedEnabled
                      ? 'Advanced metadata scan: on'
                      : 'Advanced metadata scan: off',
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
                      ? 'Run full inventory rescan'
                      : 'Rescan unavailable while loading',
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '$watcherLabel. Interactive controls are shown as buttons below.',
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InventoryInfoBadge extends StatelessWidget {
  const _InventoryInfoBadge({
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.info,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
