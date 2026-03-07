import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_typography.dart';
import '../../../providers/settings/settings_provider.dart';
import 'widgets/scaled_switch_row.dart';
import 'widgets/settings_section_card.dart';
import 'widgets/settings_slider_row.dart';
import 'sections/compression_section.dart';
import 'sections/safety_section.dart';
import 'sections/inventory_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _folderController = TextEditingController();

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(settingsProvider.select((s) => s.isLoading));
    final hasError = ref.watch(settingsProvider.select((s) => s.hasError));
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
          : Center(
              child: RepaintBoundary(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const CompressionSection(),
                      const SizedBox(height: 14),
                      const _AutomationSection(),
                      const SizedBox(height: 14),
                      _PathsSection(folderController: _folderController),
                      const SizedBox(height: 14),
                      const SafetySection(),
                      const SizedBox(height: 14),
                      const InventorySection(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sections kept here are lightweight; larger ones extracted to sections/.
// ---------------------------------------------------------------------------

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
      settingsProvider.select((s) => s.valueOrNull?.settings.cpuThreshold),
    );
    final minimizeToTray = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.settings.minimizeToTray),
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
            onChangedCommitted: (v) =>
                ref.read(settingsProvider.notifier).setIdleDuration(v.round()),
          ),
          SettingsSliderRow(
            label: 'CPU threshold',
            value: cpuThreshold.clamp(5, 20),
            min: 5,
            max: 20,
            divisions: 15,
            valueLabelBuilder: (v) => '${v.toStringAsFixed(0)}%',
            onChangedCommitted: (v) =>
                ref.read(settingsProvider.notifier).setCpuThreshold(v),
          ),
          if (!kIsWeb &&
              defaultTargetPlatform == TargetPlatform.windows &&
              minimizeToTray != null)
            ScaledSwitchRow(
              label: 'Minimize to tray on close',
              value: minimizeToTray,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setMinimizeToTray(v),
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
      settingsProvider.select((s) => s.valueOrNull?.settings.customFolders),
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
