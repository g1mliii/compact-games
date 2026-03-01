import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../widgets/scaled_switch_row.dart';
import '../widgets/settings_section_card.dart';

const ValueKey<String> _directStorageToggleKey = ValueKey<String>(
  'settingsDirectStorageToggle',
);

class SafetySection extends ConsumerStatefulWidget {
  const SafetySection({super.key});

  @override
  ConsumerState<SafetySection> createState() => _SafetySectionState();
}

class _SafetySectionState extends ConsumerState<SafetySection> {
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
          ScaledSwitchRow(
            key: _directStorageToggleKey,
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
