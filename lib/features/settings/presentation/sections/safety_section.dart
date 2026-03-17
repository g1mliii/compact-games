import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_colors.dart';
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
    final l10n = context.l10n;
    final dsOverride = ref.watch(
      settingsProvider.select(
        (s) => s.valueOrNull?.settings.directStorageOverrideEnabled,
      ),
    );
    if (dsOverride == null) return const SizedBox.shrink();

    return SettingsSectionCard(
      icon: LucideIcons.shieldAlert,
      title: l10n.settingsSafetySectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScaledSwitchRow(
            key: _directStorageToggleKey,
            label: l10n.settingsAllowDirectStorageOverride,
            value: dsOverride,
            onChanged: _onDirectStorageOverrideChanged,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  LucideIcons.alertTriangle,
                  size: 14,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    children: [
                      TextSpan(
                        text: l10n.settingsDirectStorageWarningLead,
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: l10n.settingsDirectStorageWarningBody),
                    ],
                  ),
                ),
              ),
            ],
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
        title: Text(context.l10n.settingsEnableDirectStorageOverrideTitle),
        content: Text(context.l10n.settingsEnableDirectStorageOverrideMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonEnable),
          ),
        ],
      ),
    );

    if (shouldEnable == true && mounted) {
      ref.read(settingsProvider.notifier).setDirectStorageOverrideEnabled(true);
    }
  }
}
