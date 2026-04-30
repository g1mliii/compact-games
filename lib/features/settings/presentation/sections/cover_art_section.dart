import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../models/app_settings.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../widgets/settings_section_card.dart';

const ValueKey<String> _steamGridDbBuiltInModeKey = ValueKey<String>(
  'settingsSteamGridDbBuiltInMode',
);
const ValueKey<String> _steamGridDbFieldKey = ValueKey<String>(
  'settingsSteamGridDbField',
);
const ValueKey<String> _steamGridDbSaveButtonKey = ValueKey<String>(
  'settingsSteamGridDbSaveButton',
);
const ValueKey<String> _steamGridDbRemoveButtonKey = ValueKey<String>(
  'settingsSteamGridDbRemoveButton',
);

class CoverArtSection extends ConsumerStatefulWidget {
  const CoverArtSection({super.key});

  @override
  ConsumerState<CoverArtSection> createState() => _CoverArtSectionState();
}

class _CoverArtSectionState extends ConsumerState<CoverArtSection> {
  final _controller = TextEditingController();
  ProviderSubscription<String?>? _apiKeySub;
  bool _obscured = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _apiKeySub = ref.listenManual(
      settingsProvider.select((s) => s.valueOrNull?.settings.steamGridDbApiKey),
      (previous, next) {
        if (_dirty) {
          return;
        }
        final nextValue = next ?? '';
        if (_controller.text == nextValue) {
          return;
        }
        _controller.value = TextEditingValue(
          text: nextValue,
          selection: TextSelection.collapsed(offset: nextValue.length),
        );
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _apiKeySub?.close();
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = context.l10n;
    final value = _controller.text.trim();
    ref
        .read(settingsProvider.notifier)
        .setSteamGridDbApiKey(value.isEmpty ? null : value);
    setState(() => _dirty = false);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.settingsApiKeySavedMessage),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _clear() {
    _controller.clear();
    ref.read(settingsProvider.notifier).setSteamGridDbApiKey(null);
    setState(() => _dirty = false);
  }

  Future<void> _openLink() async {
    const url = 'https://www.steamgriddb.com/profile/preferences/api';
    try {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } catch (e) {
      debugPrint('Failed to open URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final savedKey = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.settings.steamGridDbApiKey),
    );
    final providerMode = ref.watch(
      settingsProvider.select(
        (s) =>
            s.valueOrNull?.settings.coverArtProviderMode ??
            CoverArtProviderMode.bundledProxy,
      ),
    );
    final hasKey = savedKey != null && savedKey.isNotEmpty;
    final hasInput = _controller.text.trim().isNotEmpty;
    final usesOwnKey = providerMode == CoverArtProviderMode.userKey;
    final usesBuiltIn = providerMode == CoverArtProviderMode.bundledProxy;
    final statusOk = usesBuiltIn || hasKey;
    final statusColor = statusOk ? AppColors.success : AppColors.warning;
    final String statusText;
    if (usesBuiltIn) {
      statusText = l10n.settingsSteamGridDbBuiltInStatus;
    } else if (hasKey) {
      statusText = l10n.settingsSteamGridDbConnectedStatus;
    } else {
      statusText = l10n.settingsSteamGridDbMissingStatus;
    }

    return SettingsSectionCard(
      icon: LucideIcons.image,
      title: l10n.settingsIntegrationsSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Icon(
                statusOk ? LucideIcons.checkCircle2 : LucideIcons.alertCircle,
                size: 14,
                color: statusColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusText,
                  style: AppTypography.bodySmall.copyWith(color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Explanation
          Text(
            l10n.settingsSteamGridDbExplanation,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          SegmentedButton<CoverArtProviderMode>(
            segments: [
              ButtonSegment<CoverArtProviderMode>(
                value: CoverArtProviderMode.bundledProxy,
                label: Text(l10n.settingsSteamGridDbBuiltInModeLabel),
                icon: const Icon(LucideIcons.cloud, size: 14),
              ),
              ButtonSegment<CoverArtProviderMode>(
                value: CoverArtProviderMode.userKey,
                label: Text(l10n.settingsSteamGridDbUserKeyModeLabel),
                icon: const Icon(LucideIcons.keyRound, size: 14),
              ),
            ],
            selected: <CoverArtProviderMode>{providerMode},
            onSelectionChanged: (selection) {
              ref
                  .read(settingsProvider.notifier)
                  .setCoverArtProviderMode(selection.single);
            },
          ),
          const SizedBox(height: 14),

          if (usesOwnKey) ...[
            Text(
              l10n.settingsSteamGridDbUserKeyHelp,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            _StepRow(number: '1', text: l10n.settingsSteamGridDbStep1),
            const SizedBox(height: 6),
            _StepRow(number: '2', text: l10n.settingsSteamGridDbStep2),
            const SizedBox(height: 6),
            _StepRow(number: '3', text: l10n.settingsSteamGridDbStep3),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _openLink,
              icon: const Icon(LucideIcons.externalLink, size: 14),
              label: Text(l10n.settingsSteamGridDbOpenButton),
            ),
            const SizedBox(height: 14),
            TextField(
              key: _steamGridDbFieldKey,
              controller: _controller,
              obscureText: _obscured,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: (_) => setState(() => _dirty = true),
              decoration: InputDecoration(
                labelText: l10n.settingsSteamGridDbApiKeyLabel,
                hintText: l10n.settingsSteamGridDbApiKeyHint,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _obscured
                          ? l10n.settingsSteamGridDbShowKeyTooltip
                          : l10n.settingsSteamGridDbHideKeyTooltip,
                      icon: Icon(
                        _obscured ? LucideIcons.eye : LucideIcons.eyeOff,
                        size: 16,
                      ),
                      onPressed: () => setState(() => _obscured = !_obscured),
                    ),
                    if (hasInput)
                      IconButton(
                        tooltip: l10n.settingsSteamGridDbCopyKeyTooltip,
                        icon: const Icon(LucideIcons.copy, size: 16),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _controller.text),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.settingsApiKeyCopiedMessage),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: _steamGridDbSaveButtonKey,
                  onPressed: _dirty ? _save : null,
                  icon: const Icon(LucideIcons.save, size: 16),
                  label: Text(l10n.settingsSteamGridDbSaveButton),
                ),
                if (hasKey || hasInput)
                  OutlinedButton.icon(
                    key: _steamGridDbRemoveButtonKey,
                    onPressed: _clear,
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    label: Text(l10n.settingsSteamGridDbRemoveButton),
                  ),
              ],
            ),
          ] else
            KeyedSubtree(
              key: _steamGridDbBuiltInModeKey,
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.shieldCheck,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.settingsSteamGridDbManagedOnce,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: AppTypography.bodySmall.copyWith(color: AppColors.accent),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
