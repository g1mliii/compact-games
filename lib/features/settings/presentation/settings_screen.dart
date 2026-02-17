import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_typography.dart';
import '../../../models/compression_algorithm.dart';
import '../../../providers/settings/settings_provider.dart';
import 'widgets/settings_slider_row.dart';

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

  @override
  void dispose() {
    _folderController.dispose();
    _steamGridDbApiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncSettings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Failed to load settings: $error',
            style: AppTypography.bodyMedium,
          ),
        ),
        data: (state) {
          final settings = state.settings;
          if (!_steamGridDbApiKeySeeded) {
            _steamGridDbApiKeyController.text =
                settings.steamGridDbApiKey ?? '';
            _steamGridDbApiKeySeeded = true;
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _SectionCard(
                icon: LucideIcons.archive,
                title: 'Compression',
                child: Column(
                  children: [
                    _AlgorithmSelector(
                      selected: settings.algorithm,
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
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: settings.autoCompress,
                      onChanged: (enabled) => ref
                          .read(settingsProvider.notifier)
                          .setAutoCompress(enabled),
                      title: const Text('Auto-compress new games'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                icon: LucideIcons.clock3,
                title: 'Automation',
                child: Column(
                  children: [
                    SettingsSliderRow(
                      label: 'Idle threshold',
                      value: settings.idleDurationMinutes
                          .clamp(5, 30)
                          .toDouble(),
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
                      value: settings.cpuThreshold.clamp(5, 20),
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
              ),
              const SizedBox(height: 14),
              _SectionCard(
                icon: LucideIcons.folderTree,
                title: 'Paths',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _folderController,
                            decoration: const InputDecoration(
                              hintText:
                                  r'C:\Games\CustomLibrary or C:\Games\MyGame\game.exe',
                            ),
                            onSubmitted: (_) => _addFolder(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addFolder,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (settings.customFolders.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No custom paths configured.',
                          style: AppTypography.bodySmall,
                        ),
                      ),
                    ...settings.customFolders.map(
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
              ),
              const SizedBox(height: 14),
              _SectionCard(
                icon: LucideIcons.shieldAlert,
                title: 'Safety',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: settings.directStorageOverrideEnabled,
                      onChanged: (enabled) =>
                          _onDirectStorageOverrideChanged(enabled),
                      title: const Text('Allow DirectStorage override'),
                    ),
                    const Text(
                      'Warning: overriding DirectStorage protection may reduce in-game performance.',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                icon: LucideIcons.slidersHorizontal,
                title: 'Inventory',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: settings.inventoryAdvancedScanEnabled,
                      onChanged: (enabled) => ref
                          .read(settingsProvider.notifier)
                          .setInventoryAdvancedScanEnabled(enabled),
                      title: const Text('Enable full metadata inventory scan'),
                    ),
                    const Text(
                      'When enabled, Inventory shows a "Run Full Inventory Rescan" action that performs a deeper metadata pass.',
                      style: AppTypography.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _steamGridDbApiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'SteamGridDB API key (optional)',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _saveSteamGridDbApiKey(),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: _saveSteamGridDbApiKey,
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
              ),
            ],
          );
        },
      ),
    );
  }

  void _addFolder() {
    final value = _folderController.text.trim();
    if (value.isEmpty) {
      return;
    }
    ref.read(settingsProvider.notifier).addCustomFolder(value);
    _folderController.clear();
  }

  void _saveSteamGridDbApiKey() {
    final value = _steamGridDbApiKeyController.text.trim();
    ref
        .read(settingsProvider.notifier)
        .setSteamGridDbApiKey(value.isEmpty ? null : value);
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

    if (shouldEnable == true) {
      ref.read(settingsProvider.notifier).setDirectStorageOverrideEnabled(true);
    }
  }
}

class _AlgorithmSelector extends StatelessWidget {
  const _AlgorithmSelector({required this.selected, required this.onSelected});

  final CompressionAlgorithm selected;
  final ValueChanged<CompressionAlgorithm> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CompressionAlgorithm>(
      tooltip: 'Algorithm',
      popUpAnimationStyle: AnimationStyle.noAnimation,
      onSelected: onSelected,
      itemBuilder: (context) => CompressionAlgorithm.values
          .map(
            (algo) => PopupMenuItem<CompressionAlgorithm>(
              value: algo,
              child: Text(
                algo.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall,
              ),
            ),
          )
          .toList(growable: false),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Algorithm',
          isDense: true,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(LucideIcons.chevronDown, size: 16),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 8),
                Text(title, style: AppTypography.headingSmall),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
