import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../widgets/settings_section_card.dart';

const ValueKey<String> _ioOverrideSelectorKey = ValueKey<String>(
  'settingsIoOverrideSelector',
);

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
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 10),
          RepaintBoundary(
            child: IoOverrideSelector(
              selected: ioOverride,
              onSelected: (value) => ref
                  .read(settingsProvider.notifier)
                  .setIoParallelismOverride(value),
            ),
          ),
        ],
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

  static const double _controlHeight = 40;
  static const double _menuItemHeight = 34;
  static const int _autoValue = 0;

  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: _ioOverrideSelectorKey,
          height: _controlHeight,
          child: PopupMenuButton<int>(
            tooltip: 'I/O thread override',
            popUpAnimationStyle: AnimationStyle.noAnimation,
            padding: EdgeInsets.zero,
            onSelected: (value) {
              onSelected(value == _autoValue ? null : value);
            },
            itemBuilder: (context) => <PopupMenuEntry<int>>[
              PopupMenuItem<int>(
                value: _autoValue,
                height: _menuItemHeight,
                child: _MenuItemLabel(
                  text: _labelFor(null),
                  selected: selected == null,
                ),
              ),
              for (var i = 1; i <= CompressionSection._maxIoOverride; i++)
                PopupMenuItem<int>(
                  value: i,
                  height: _menuItemHeight,
                  child: _MenuItemLabel(
                    text: _labelFor(i),
                    selected: selected == i,
                  ),
                ),
            ],
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'I/O Threads',
                isDense: true,
              ),
              child: SizedBox.expand(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _labelFor(selected),
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
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.only(left: 2),
          child: Text(
            'Auto recommended. Override only for advanced tuning.',
            style: AppTypography.label,
          ),
        ),
      ],
    );
  }

  static String _labelFor(int? value) {
    if (value == null) {
      return 'Auto';
    }
    return '$value thread${value == 1 ? '' : 's'}';
  }
}

class _MenuItemLabel extends StatelessWidget {
  const _MenuItemLabel({required this.text, required this.selected});

  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySmall.copyWith(
          color: color,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}
