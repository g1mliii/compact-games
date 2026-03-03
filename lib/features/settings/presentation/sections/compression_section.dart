import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../widgets/settings_section_card.dart';

class CompressionSection extends ConsumerWidget {
  const CompressionSection({super.key});
  static const int _maxIoOverride = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.settings),
    );
    if (settings == null) return const SizedBox.shrink();
    final algorithm = settings.algorithm;
    final ioOverride = settings.ioParallelismOverride;

    return SettingsSectionCard(
      icon: LucideIcons.archive,
      title: 'Compression',
      child: Column(
        children: [
          AlgorithmSelector(
            selected: algorithm,
            onSelected: (value) =>
                ref.read(settingsProvider.notifier).updateAlgorithm(value),
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'XPRESS 8K is the recommended default for most games.',
              style: AppTypography.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: ioOverride,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'I/O Thread Override (Expert)',
              helperText:
                  'Auto is recommended. Override only for advanced tuning.',
            ),
            items: <DropdownMenuItem<int?>>[
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Auto'),
              ),
              for (var i = 1; i <= _maxIoOverride; i++)
                DropdownMenuItem<int?>(
                  value: i,
                  child: Text('$i thread${i == 1 ? '' : 's'}'),
                ),
            ],
            onChanged: (value) => ref
                .read(settingsProvider.notifier)
                .setIoParallelismOverride(value),
          ),
        ],
      ),
    );
  }
}
