import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

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

/// Inventory section owns its own local state (API key reveal toggle,
/// controller, seeding) so that toggling reveal never rebuilds the
/// parent SettingsScreen or sibling sections.
class InventorySection extends ConsumerStatefulWidget {
  const InventorySection({super.key});

  @override
  ConsumerState<InventorySection> createState() => _InventorySectionState();
}

class _InventorySectionState extends ConsumerState<InventorySection> {
  final TextEditingController _apiKeyController = TextEditingController();
  ProviderSubscription<String?>? _apiKeySub;
  bool _apiKeySeeded = false;
  bool _revealApiKey = false;

  @override
  void initState() {
    super.initState();
    _apiKeySub = ref.listenManual(
      settingsProvider.select((s) => s.valueOrNull?.settings.steamGridDbApiKey),
      (prev, next) {
        if (!_apiKeySeeded && next != null) {
          _apiKeyController.text = next;
          _apiKeySeeded = true;
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _apiKeySub?.close();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      title: 'Inventory',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WatcherStatusBanner(),
          SizedBox(
            width: double.infinity,
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
              label: Text(autoCompress ? 'Pause watcher' : 'Resume watcher'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            autoCompress
                ? 'Watcher automation is enabled.'
                : 'Watcher automation is disabled.',
            style: AppTypography.bodySmall,
          ),
          ScaledSwitchRow(
            key: _advancedToggleKey,
            label: 'Enable full metadata inventory scan',
            value: advancedScan,
            onChanged: (enabled) => ref
                .read(settingsProvider.notifier)
                .setInventoryAdvancedScanEnabled(enabled),
          ),
          const Text(
            'When enabled, Inventory shows a "Run Full Inventory Rescan" action that performs a deeper metadata pass.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _apiKeyController,
            obscureText: !_revealApiKey,
            enableSuggestions: false,
            autocorrect: false,
            decoration:
                const InputDecoration(
                  labelText: 'SteamGridDB API key (optional)',
                  isDense: true,
                ).copyWith(
                  suffixIcon: IconButton(
                    tooltip: _revealApiKey ? 'Hide key' : 'Show key',
                    icon: Icon(
                      _revealApiKey ? LucideIcons.eyeOff : LucideIcons.eye,
                    ),
                    onPressed: _toggleReveal,
                  ),
                ),
            onSubmitted: (_) => _saveApiKey(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _saveApiKey,
              child: const Text('Save API Key'),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Used as fallback for Epic/GOG/Ubisoft when local art cannot be found.',
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }

  void _toggleReveal() {
    setState(() => _revealApiKey = !_revealApiKey);
  }

  void _saveApiKey() {
    final value = _apiKeyController.text.trim();
    ref
        .read(settingsProvider.notifier)
        .setSteamGridDbApiKey(value.isEmpty ? null : value);
  }
}
