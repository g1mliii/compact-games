import 'package:flutter/material.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/localization/presentation_labels.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../models/compression_algorithm.dart';
import 'static_popup_selector.dart';

class AlgorithmSelector extends StatelessWidget {
  const AlgorithmSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final CompressionAlgorithm selected;
  final ValueChanged<CompressionAlgorithm> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return StaticPopupSelector<CompressionAlgorithm>(
      labelText: l10n.settingsAlgorithmLabel,
      tooltip: l10n.settingsAlgorithmTooltip,
      selectedLabel: selected.localizedLabel(l10n),
      items: CompressionAlgorithm.values
          .map(
            (algo) => StaticPopupSelectorItem<CompressionAlgorithm>(
              value: algo,
              label: algo.localizedLabel(l10n),
              selected: algo == selected,
            ),
          )
          .toList(growable: false),
      onSelected: onSelected,
    );
  }
}

class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: 8),
                  Text(title, style: AppTypography.headingSmall),
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
