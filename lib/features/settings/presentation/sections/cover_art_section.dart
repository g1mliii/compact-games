import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../widgets/settings_section_card.dart';

class CoverArtSection extends ConsumerStatefulWidget {
  const CoverArtSection({super.key});

  @override
  ConsumerState<CoverArtSection> createState() => _CoverArtSectionState();
}

class _CoverArtSectionState extends ConsumerState<CoverArtSection> {
  final _controller = TextEditingController();
  bool _obscured = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromSettings());
  }

  void _syncFromSettings() {
    final key = ref.read(
      settingsProvider.select((s) => s.valueOrNull?.settings.steamGridDbApiKey),
    );
    if (key != null && _controller.text.isEmpty) {
      _controller.text = key;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    ref
        .read(settingsProvider.notifier)
        .setSteamGridDbApiKey(value.isEmpty ? null : value);
    setState(() => _dirty = false);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('API key saved.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _clear() {
    _controller.clear();
    ref.read(settingsProvider.notifier).setSteamGridDbApiKey(null);
    setState(() => _dirty = false);
  }

  Future<void> _openLink() async {
    await Process.run('cmd', [
      '/c',
      'start',
      '',
      'https://www.steamgriddb.com/profile/preferences/api',
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final savedKey = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.settings.steamGridDbApiKey),
    );
    final hasKey = savedKey != null && savedKey.isNotEmpty;

    return SettingsSectionCard(
      icon: LucideIcons.image,
      title: 'Cover Art',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Icon(
                hasKey ? LucideIcons.checkCircle2 : LucideIcons.alertCircle,
                size: 14,
                color: hasKey ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 6),
              Text(
                hasKey
                    ? 'SteamGridDB connected — game covers will load automatically.'
                    : 'No API key set — game covers will not load.',
                style: AppTypography.bodySmall.copyWith(
                  color: hasKey ? AppColors.success : AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Explanation
          Text(
            'PressPlay uses SteamGridDB to fetch high-quality cover art for your games. '
            'Getting a key is free and takes about 30 seconds — you just need a Steam account.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // Steps
          const _StepRow(
            number: '1',
            text: 'Click "Get API Key" below to open SteamGridDB in your browser.',
          ),
          const SizedBox(height: 6),
          const _StepRow(
            number: '2',
            text: 'Sign in with your Steam account (no registration required).',
          ),
          const SizedBox(height: 6),
          const _StepRow(
            number: '3',
            text: 'Click "Generate API Key", then copy and paste it into the field below.',
          ),
          const SizedBox(height: 16),

          // Open link button
          OutlinedButton.icon(
            onPressed: _openLink,
            icon: const Icon(LucideIcons.externalLink, size: 14),
            label: const Text('Get API Key on SteamGridDB'),
          ),
          const SizedBox(height: 16),

          // API key input
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  obscureText: _obscured,
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: InputDecoration(
                    labelText: 'SteamGridDB API Key',
                    hintText: 'Paste your key here',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: _obscured ? 'Show key' : 'Hide key',
                          icon: Icon(
                            _obscured
                                ? LucideIcons.eye
                                : LucideIcons.eyeOff,
                            size: 16,
                          ),
                          onPressed: () =>
                              setState(() => _obscured = !_obscured),
                        ),
                        if (hasKey && !_dirty)
                          IconButton(
                            tooltip: 'Copy key',
                            icon: const Icon(LucideIcons.copy, size: 16),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _controller.text),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('API key copied.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _dirty ? _save : null,
                    child: const Text('Save'),
                  ),
                  if (hasKey) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _clear,
                      child: const Text('Remove'),
                    ),
                  ],
                ],
              ),
            ],
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
