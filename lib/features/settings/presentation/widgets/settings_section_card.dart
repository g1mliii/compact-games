import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../models/compression_algorithm.dart';

class AlgorithmSelector extends StatelessWidget {
  const AlgorithmSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const double _controlHeight = 40;

  final CompressionAlgorithm selected;
  final ValueChanged<CompressionAlgorithm> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _controlHeight,
      child: PopupMenuButton<CompressionAlgorithm>(
        tooltip: 'Algorithm',
        popUpAnimationStyle: AnimationStyle.noAnimation,
        padding: EdgeInsets.zero,
        onSelected: onSelected,
        itemBuilder: (context) => CompressionAlgorithm.values
            .map(
              (algo) => PopupMenuItem<CompressionAlgorithm>(
                value: algo,
                child: Text(
                  algo.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall,
                ),
              ),
            )
            .toList(growable: false),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Algorithm',
            isDense: true,
          ),
          child: SizedBox.expand(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.chevronDown, size: 16),
              ],
            ),
          ),
        ),
      ),
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
    return Card(
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
    );
  }
}
