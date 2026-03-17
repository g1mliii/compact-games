import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/localization/app_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../providers/settings/settings_provider.dart';
import 'sections/language_section.dart';
import 'widgets/scaled_switch_row.dart';
import 'widgets/settings_section_card.dart';
import 'widgets/settings_slider_row.dart';
import 'sections/compression_section.dart';
import 'sections/cover_art_section.dart';
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
    final l10n = context.l10n;
    final isLoading = ref.watch(settingsProvider.select((s) => s.isLoading));
    final hasError = ref.watch(settingsProvider.select((s) => s.hasError));
    final errorValue = ref.watch(
      settingsProvider.select((s) => s.hasError ? s.error : null),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : hasError
          ? Center(
              child: Text(
                l10n.settingsLoadFailed('${errorValue ?? ''}'),
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
                      const LanguageSection(),
                      const SizedBox(height: 14),
                      const CompressionSection(),
                      const SizedBox(height: 14),
                      const _AutomationSection(),
                      const SizedBox(height: 14),
                      _PathsSection(folderController: _folderController),
                      const SizedBox(height: 14),
                      const CoverArtSection(),
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
    final l10n = context.l10n;
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
      title: l10n.settingsAutomationSectionTitle,
      child: Column(
        children: [
          SettingsSliderRow(
            label: l10n.settingsIdleThresholdLabel,
            value: idleMinutes.clamp(5, 30).toDouble(),
            min: 5,
            max: 30,
            divisions: 25,
            valueLabelBuilder: (v) => l10n.settingsMinutesShort(v.round()),
            valueColorBuilder: _idleThresholdColor,
            onChangedCommitted: (v) =>
                ref.read(settingsProvider.notifier).setIdleDuration(v.round()),
          ),
          SettingsSliderRow(
            label: l10n.settingsCpuThresholdLabel,
            value: cpuThreshold.clamp(5, 20),
            min: 5,
            max: 20,
            divisions: 15,
            valueLabelBuilder: (v) =>
                l10n.settingsPercentShort(v.toStringAsFixed(0)),
            valueColorBuilder: _cpuThresholdColor,
            onChangedCommitted: (v) =>
                ref.read(settingsProvider.notifier).setCpuThreshold(v),
          ),
          if (!kIsWeb &&
              defaultTargetPlatform == TargetPlatform.windows &&
              minimizeToTray != null)
            ScaledSwitchRow(
              label: l10n.settingsMinimizeToTrayOnCloseLabel,
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
    final l10n = context.l10n;
    final customFolders = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.settings.customFolders),
    );
    if (customFolders == null) return const SizedBox.shrink();

    return SettingsSectionCard(
      icon: LucideIcons.folderTree,
      title: l10n.settingsPathsSectionTitle,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: folderController,
                  decoration: InputDecoration(
                    hintText: l10n.settingsPathsHint,
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                  ),
                  onSubmitted: (_) => _addFolder(ref),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _addFolder(ref),
                child: Text(l10n.commonAdd),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (customFolders.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.settingsNoCustomPaths,
                style: AppTypography.bodySmall,
              ),
            ),
          ...customFolders.map(
            (path) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(path, style: AppTypography.bodySmall),
              trailing: IconButton(
                tooltip: l10n.settingsRemovePathTooltip,
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

Color _idleThresholdColor(double value) {
  if (value <= 8) {
    return AppColors.warning;
  }
  if (value >= 22) {
    return AppColors.success;
  }
  if (value >= 15) {
    return AppColors.richGold;
  }
  return AppColors.textPrimary;
}

Color _cpuThresholdColor(double value) {
  if (value >= 18) {
    return AppColors.error;
  }
  if (value >= 15) {
    return AppColors.warning;
  }
  if (value >= 10) {
    return AppColors.richGold;
  }
  return AppColors.textPrimary;
}
