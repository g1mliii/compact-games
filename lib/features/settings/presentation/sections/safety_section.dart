import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../../../../services/unsupported_report_sync_service.dart';
import '../widgets/scaled_switch_row.dart';
import '../widgets/settings_section_card.dart';

const ValueKey<String> _directStorageToggleKey = ValueKey<String>(
  'settingsDirectStorageToggle',
);
const ValueKey<String> _unsupportedReportSharingToggleKey = ValueKey<String>(
  'settingsUnsupportedReportSharingToggle',
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
        (s) => s.value?.settings.directStorageOverrideEnabled,
      ),
    );
    final shareUnsupportedReports = ref.watch(
      settingsProvider.select((s) => s.value?.settings.shareUnsupportedReports),
    );
    if (dsOverride == null || shareUnsupportedReports == null) {
      return const SizedBox.shrink();
    }

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
            enableLabelSurfaceHover: false,
            showLabelSurfaceDecoration: false,
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
                child: Text(
                  l10n.settingsDirectStorageWarningBody,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          ScaledSwitchRow(
            key: _unsupportedReportSharingToggleKey,
            label: l10n.settingsShareUnsupportedReportsLabel,
            value: shareUnsupportedReports,
            onChanged: _onShareUnsupportedReportsChanged,
            enableLabelSurfaceHover: false,
            showLabelSurfaceDecoration: false,
          ),
          Text(
            l10n.settingsShareUnsupportedReportsDescription,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
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

  Future<void> _onShareUnsupportedReportsChanged(bool enabled) async {
    // Consent changes are persisted immediately rather than through the 500 ms
    // debounce: nothing flushes settings on quit, so a revocation made just
    // before closing the app would otherwise be lost and sharing would resume
    // on the next launch.
    if (!enabled) {
      final notifier = ref.read(settingsProvider.notifier);
      notifier.setShareUnsupportedReports(false);
      await notifier.flush();
      return;
    }

    final shouldEnable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsShareUnsupportedReportsConfirmTitle),
        content: Text(
          context.l10n.settingsShareUnsupportedReportsConfirmMessage,
        ),
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
      final notifier = ref.read(settingsProvider.notifier);
      notifier.setShareUnsupportedReports(true);
      UnsupportedReportSyncService.instance.notePotentialChange(
        ProviderScope.containerOf(context, listen: false),
      );
      await notifier.flush();
    }
  }
}
