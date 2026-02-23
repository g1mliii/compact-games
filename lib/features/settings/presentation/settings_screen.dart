import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../providers/settings/settings_provider.dart';
import '../../../providers/system/auto_compression_status_provider.dart';
import 'widgets/settings_section_card.dart';
import 'widgets/settings_slider_row.dart';

const ValueKey<String> _settingsWatcherToggleButtonKey = ValueKey<String>(
  'settingsWatcherToggleButton',
);
const ValueKey<String> _settingsDirectStorageToggleKey = ValueKey<String>(
  'settingsDirectStorageToggle',
);
const ValueKey<String> _settingsInventoryAdvancedToggleKey = ValueKey<String>(
  'settingsInventoryAdvancedToggle',
);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _folderController = TextEditingController();
  final TextEditingController _steamGridDbApiKeyController =
      TextEditingController();
  bool _steamGridDbApiKeySeeded = false;
  bool _revealSteamGridDbApiKey = false;

  @override
  void initState() {
    super.initState();
    // Seed API key controller once when settings first become available.
    ref.listenManual(
      settingsProvider.select(
        (s) => s.valueOrNull?.settings.steamGridDbApiKey,
      ),
      (prev, next) {
        if (!_steamGridDbApiKeySeeded && next != null) {
          _steamGridDbApiKeyController.text = next;
          _steamGridDbApiKeySeeded = true;
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _folderController.dispose();
    _steamGridDbApiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(
      settingsProvider.select((s) => s.isLoading),
    );
    final hasError = ref.watch(
      settingsProvider.select((s) => s.hasError),
    );
    final errorValue = ref.watch(
      settingsProvider.select((s) => s.hasError ? s.error : null),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : hasError
              ? Center(
                  child: Text(
                    'Failed to load settings: $errorValue',
                    style: AppTypography.bodyMedium,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const _CompressionSection(),
                    const SizedBox(height: 14),
                    const _AutomationSection(),
                    const SizedBox(height: 14),
                    _PathsSection(folderController: _folderController),
                    const SizedBox(height: 14),
                    const _SafetySection(),
                    const SizedBox(height: 14),
                    _InventorySection(
                      steamGridDbApiKeyController: _steamGridDbApiKeyController,
                      revealSteamGridDbApiKey: _revealSteamGridDbApiKey,
                      onToggleReveal: () {
                        setState(() {
                          _revealSteamGridDbApiKey = !_revealSteamGridDbApiKey;
                        });
                      },
                    ),
                  ],
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-section ConsumerWidgets — each selects only its relevant fields.
// ---------------------------------------------------------------------------

class _CompressionSection extends ConsumerWidget {
  const _CompressionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final algorithm = ref.watch(
      settingsProvider.select(
        (s) => s.valueOrNull?.settings.algorithm,
      ),
    );
    if (algorithm == null) return const SizedBox.shrink();

    return SettingsSectionCard(
      icon: LucideIcons.archive,
      title: 'Compression',
      child: Column(
        children: [
          AlgorithmSelector(
            selected: algorithm,
            onSelected: (value) => ref
                .read(settingsProvider.notifier)
                .updateAlgorithm(value),
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'XPRESS 8K is the recommended default for most games.',
              style: AppTypography.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutomationSection extends ConsumerWidget {
  const _AutomationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idleMinutes = ref.watch(
      settingsProvider.select(
        (s) => s.valueOrNull?.settings.idleDurationMinutes,
      ),
    );
    final cpuThreshold = ref.watch(
      settingsProvider.select(
        (s) => s.valueOrNull?.settings.cpuThreshold,
      ),
    );
    if (idleMinutes == null || cpuThreshold == null) {
      return const SizedBox.shrink();
    }

    return SettingsSectionCard(
      icon: LucideIcons.clock3,
      title: 'Automation',
      child: Column(
        children: [
          SettingsSliderRow(
            label: 'Idle threshold',
            value: idleMinutes.clamp(5, 30).toDouble(),
            min: 5,
            max: 30,
            divisions: 25,
            valueLabelBuilder: (v) => '${v.round()} min',
            onChangedCommitted: (v) => ref
                .read(settingsProvider.notifier)
                .setIdleDuration(v.round()),
          ),
          SettingsSliderRow(
            label: 'CPU threshold',
            value: cpuThreshold.clamp(5, 20),
            min: 5,
            max: 20,
            divisions: 15,
            valueLabelBuilder: (v) => '${v.toStringAsFixed(0)}%',
            onChangedCommitted: (v) => ref
                .read(settingsProvider.notifier)
                .setCpuThreshold(v),
          ),
        ],
      ),
    );
  }
}

class _PathsSection extends ConsumerWidget {
  const _PathsSection({required this.folderController});

  final TextEditingController folderController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customFolders = ref.watch(
      settingsProvider.select(
        (s) => s.valueOrNull?.settings.customFolders,
      ),
    );
    if (customFolders == null) return const SizedBox.shrink();

    return SettingsSectionCard(
      icon: LucideIcons.folderTree,
      title: 'Paths',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: folderController,
                  decoration: const InputDecoration(
                    hintText:
                        r'C:\Games\CustomLibrary or C:\Games\MyGame\game.exe',
                  ),
                  onSubmitted: (_) => _addFolder(ref),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _addFolder(ref),
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (customFolders.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No custom paths configured.',
                style: AppTypography.bodySmall,
              ),
            ),
          ...customFolders.map(
            (path) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(path, style: AppTypography.bodySmall),
              trailing: IconButton(
                tooltip: 'Remove path',
                icon: const Icon(LucideIcons.trash2, size: 16),
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .removeCustomFolder(path),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addFolder(WidgetRef ref) {
    final value = folderController.text.trim();
    if (value.isEmpty) return;
    ref.read(settingsProvider.notifier).addCustomFolder(value);
    folderController.clear();
  }
}

class _SafetySection extends ConsumerStatefulWidget {
  const _SafetySection();

  @override
  ConsumerState<_SafetySection> createState() => _SafetySectionState();
}

class _SafetySectionState extends ConsumerState<_SafetySection> {
  @override
  Widget build(BuildContext context) {
    final dsOverride = ref.watch(
      settingsProvider.select(
        (s) => s.valueOrNull?.settings.directStorageOverrideEnabled,
      ),
    );
    if (dsOverride == null) return const SizedBox.shrink();

    return SettingsSectionCard(
      icon: LucideIcons.shieldAlert,
      title: 'Safety',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScaledSwitchRow(
            key: _settingsDirectStorageToggleKey,
            label: 'Allow DirectStorage override',
            value: dsOverride,
            onChanged: _onDirectStorageOverrideChanged,
          ),
          const Text(
            'Warning: overriding DirectStorage protection may reduce in-game performance.',
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _onDirectStorageOverrideChanged(bool enabled) async {
    if (!enabled) {
      ref
          .read(settingsProvider.notifier)
          .setDirectStorageOverrideEnabled(false);
      return;
    }

    final shouldEnable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable DirectStorage Override?'),
        content: const Text(
          'This allows compression on DirectStorage-tagged games and may impact performance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (shouldEnable == true && mounted) {
      ref.read(settingsProvider.notifier).setDirectStorageOverrideEnabled(true);
    }
  }
}

class _InventorySection extends ConsumerWidget {
  const _InventorySection({
    required this.steamGridDbApiKeyController,
    required this.revealSteamGridDbApiKey,
    required this.onToggleReveal,
  });

  final TextEditingController steamGridDbApiKeyController;
  final bool revealSteamGridDbApiKey;
  final VoidCallback onToggleReveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoCompress = ref.watch(
      settingsProvider.select(
        (s) => s.valueOrNull?.settings.autoCompress,
      ),
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
          const _WatcherStatusBanner(),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton.icon(
              key: _settingsWatcherToggleButtonKey,
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .setAutoCompress(!autoCompress),
              icon: Icon(
                autoCompress ? LucideIcons.pause : LucideIcons.play,
                size: 16,
              ),
              label: Text(
                autoCompress ? 'Pause watcher' : 'Resume watcher',
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            autoCompress
                ? 'Watcher automation is enabled.'
                : 'Watcher automation is disabled.',
            style: AppTypography.bodySmall,
          ),
          _ScaledSwitchRow(
            key: _settingsInventoryAdvancedToggleKey,
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
            controller: steamGridDbApiKeyController,
            obscureText: !revealSteamGridDbApiKey,
            enableSuggestions: false,
            autocorrect: false,
            decoration:
                const InputDecoration(
                  labelText: 'SteamGridDB API key (optional)',
                  isDense: true,
                ).copyWith(
                  suffixIcon: IconButton(
                    tooltip: revealSteamGridDbApiKey ? 'Hide key' : 'Show key',
                    icon: Icon(
                      revealSteamGridDbApiKey
                          ? LucideIcons.eyeOff
                          : LucideIcons.eye,
                    ),
                    onPressed: onToggleReveal,
                  ),
                ),
            onSubmitted: (_) => _saveSteamGridDbApiKey(ref),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => _saveSteamGridDbApiKey(ref),
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

  void _saveSteamGridDbApiKey(WidgetRef ref) {
    final value = steamGridDbApiKeyController.text.trim();
    ref
        .read(settingsProvider.notifier)
        .setSteamGridDbApiKey(value.isEmpty ? null : value);
  }
}

class _ScaledSwitchRow extends StatelessWidget {
  const _ScaledSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Transform.scale(
              scale: 0.84,
              alignment: Alignment.centerRight,
              child: Switch(
                value: value,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatcherStatusBanner extends ConsumerWidget {
  const _WatcherStatusBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watcherActive = ref.watch(
      autoCompressionRunningProvider.select(
        (value) => value.valueOrNull ?? false,
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Text(
        watcherActive ? 'Watcher status: active' : 'Watcher status: paused',
        style: AppTypography.bodySmall.copyWith(
          color: watcherActive ? AppColors.success : AppColors.warning,
        ),
      ),
    );
  }
}
