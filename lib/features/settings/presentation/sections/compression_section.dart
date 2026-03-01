import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../widgets/settings_section_card.dart';

class CompressionSection extends ConsumerWidget {
  const CompressionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final algorithm = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.settings.algorithm),
    );
    if (algorithm == null) return const SizedBox.shrink();

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
        ],
      ),
    );
  }
}
