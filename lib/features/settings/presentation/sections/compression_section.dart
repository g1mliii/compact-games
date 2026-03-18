import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_localization.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../models/compression_algorithm.dart';
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
    return _IoOverrideInput(
      selected: selected,
      onSelected: onSelected,
      labelText: l10n.settingsIoThreadsLabel,
      hintText: l10n.settingsIoThreadsAuto,
    );
  }
}

class _IoThreadsHelpText extends StatelessWidget {
  const _IoThreadsHelpText();

  @override
  Widget build(BuildContext context) {
    return Text(context.l10n.settingsIoThreadsHelp, style: AppTypography.label);
  }
}

class _IoOverrideInput extends StatefulWidget {
  const _IoOverrideInput({
    required this.selected,
    required this.onSelected,
    required this.labelText,
    required this.hintText,
  });

  final int? selected;
  final ValueChanged<int?> onSelected;
  final String labelText;
  final String hintText;

  @override
  State<_IoOverrideInput> createState() => _IoOverrideInputState();
}

class _IoOverrideInputState extends State<_IoOverrideInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.selected?.toString() ?? '',
  );
  late final FocusNode _focusNode = FocusNode()
    ..addListener(() {
      if (!_focusNode.hasFocus) {
        _commit();
      }
    });

  @override
  void didUpdateWidget(covariant _IoOverrideInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      final nextText = widget.selected?.toString() ?? '';
      if (_controller.text != nextText) {
        _controller.value = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: nextText.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final raw = _controller.text.trim();
    int? nextValue;
    if (raw.isEmpty) {
      nextValue = null;
    } else {
      final parsed = int.tryParse(raw);
      if (parsed == null) {
        nextValue = null;
      } else {
        final clamped = parsed
            .clamp(1, CompressionSection._maxIoOverride)
            .toInt();
        final normalized = '$clamped';
        if (normalized != raw) {
          _controller.value = TextEditingValue(
            text: normalized,
            selection: TextSelection.collapsed(offset: normalized.length),
          );
        }
        nextValue = clamped;
      }
    }

    if (nextValue == widget.selected) {
      return;
    }
    widget.onSelected(nextValue);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: SizedBox(
            height: 40,
            child: TextField(
              key: _ioOverrideSelectorKey,
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: InputDecoration(
                labelText: widget.labelText,
                hintText: widget.hintText,
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              ),
              onSubmitted: (_) => _commit(),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.only(left: 2),
          child: _IoThreadsHelpText(),
        ),
      ],
    );
  }
}
