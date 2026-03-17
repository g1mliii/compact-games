import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pressplay/l10n/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../models/compression_algorithm.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../widgets/settings_section_card.dart';
import '../widgets/static_popup_selector.dart';

const ValueKey<String> _ioOverrideSelectorKey = ValueKey<String>(
  'settingsIoOverrideSelector',
);

class CompressionSection extends ConsumerWidget {
  const CompressionSection({super.key});
  static const int _maxIoOverride = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSettings = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.settings != null),
    );
    if (!hasSettings) return const SizedBox.shrink();
    final l10n = context.l10n;

    return SettingsSectionCard(
      icon: LucideIcons.archive,
      title: l10n.settingsCompressionSectionTitle,
      child: const _CompressionSectionBody(),
    );
  }
}

class _CompressionSectionBody extends StatelessWidget {
  const _CompressionSectionBody();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AlgorithmSelectorHost(),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.settingsAlgorithmRecommendedHint,
            style: AppTypography.bodySmall,
          ),
        ),
        const SizedBox(height: 10),
        const _IoOverrideSelectorHost(),
      ],
    );
  }
}

class _AlgorithmSelectorHost extends ConsumerWidget {
  const _AlgorithmSelectorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final algorithm = ref.watch(
      settingsProvider.select(
        (s) =>
            s.valueOrNull?.settings.algorithm ?? CompressionAlgorithm.xpress8k,
      ),
    );

    return RepaintBoundary(
      child: AlgorithmSelector(
        selected: algorithm,
        onSelected: (value) =>
            ref.read(settingsProvider.notifier).updateAlgorithm(value),
      ),
    );
  }
}

class _IoOverrideSelectorHost extends ConsumerWidget {
  const _IoOverrideSelectorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ioOverride = ref.watch(
      settingsProvider.select(
        (s) => s.valueOrNull?.settings.ioParallelismOverride,
      ),
    );

    return RepaintBoundary(
      child: IoOverrideSelector(
        selected: ioOverride,
        onSelected: (value) =>
            ref.read(settingsProvider.notifier).setIoParallelismOverride(value),
      ),
    );
  }
}

class IoOverrideSelector extends StatelessWidget {
  const IoOverrideSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaticPopupSelector<int?>(
          key: _ioOverrideSelectorKey,
          labelText: l10n.settingsIoThreadsLabel,
          tooltip: l10n.settingsIoThreadsTooltip,
          selectedLabel: _labelFor(l10n, selected),
          items: <StaticPopupSelectorItem<int?>>[
            StaticPopupSelectorItem<int?>(
              value: null,
              label: _labelFor(l10n, null),
              selected: selected == null,
            ),
            for (var i = 1; i <= CompressionSection._maxIoOverride; i++)
              StaticPopupSelectorItem<int?>(
                value: i,
                label: _labelFor(l10n, i),
                selected: selected == i,
              ),
          ],
          onSelected: onSelected,
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.only(left: 2),
          child: _IoThreadsHelpText(),
        ),
      ],
    );
  }

  static String _labelFor(AppLocalizations l10n, int? value) {
    if (value == null) {
      return l10n.settingsIoThreadsAuto;
    }
    return l10n.settingsIoThreadsCount(value);
  }
}

class _IoThreadsHelpText extends StatelessWidget {
  const _IoThreadsHelpText();

  @override
  Widget build(BuildContext context) {
    return Text(context.l10n.settingsIoThreadsHelp, style: AppTypography.label);
  }
}
