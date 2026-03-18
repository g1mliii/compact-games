import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';

typedef SliderDirectEntryRequest =
    Future<double?> Function(
      BuildContext context,
      double currentValue,
      double min,
      double max,
    );

class SettingsSliderRow extends StatefulWidget {
  const SettingsSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabelBuilder,
    required this.onChangedCommitted,
    this.valueColorBuilder,
    this.valueKey,
    this.onRequestDirectEntry,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double value) valueLabelBuilder;
  final ValueChanged<double> onChangedCommitted;
  final Color Function(double value)? valueColorBuilder;
  final Key? valueKey;
  final SliderDirectEntryRequest? onRequestDirectEntry;

  @override
  State<SettingsSliderRow> createState() => _SettingsSliderRowState();
}

class _SettingsSliderRowState extends State<SettingsSliderRow> {
  static const double _epsilon = 0.001;
  late double _draftValue;
  bool _dragging = false;
  SliderThemeData? _cachedSliderTheme;

  @override
  void initState() {
    super.initState();
    _draftValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant SettingsSliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragging) {
      return;
    }
    if ((widget.value - _draftValue).abs() > _epsilon) {
      _draftValue = widget.value;
    }
  }

  Future<void> _handleDirectEntry() async {
    final request = widget.onRequestDirectEntry;
    if (request == null) {
      return;
    }
    final nextValue = await request(
      context,
      _draftValue,
      widget.min,
      widget.max,
    );
    if (nextValue == null) {
      return;
    }

    final clampedValue = nextValue.clamp(widget.min, widget.max).toDouble();
    setState(() {
      _dragging = false;
      _draftValue = clampedValue;
    });

    if ((widget.value - clampedValue).abs() <= _epsilon) {
      return;
    }
    widget.onChangedCommitted(clampedValue);
  }

  @override
  Widget build(BuildContext context) {
    final valueLabel = widget.valueLabelBuilder(_draftValue);
    final valueColor =
        widget.valueColorBuilder?.call(_draftValue) ?? AppColors.textPrimary;
    final valueText = Text(
      valueLabel,
      style: AppTypography.bodySmall.copyWith(
        color: valueColor,
        fontWeight: FontWeight.w700,
      ),
    );
    final valueWidget = widget.onRequestDirectEntry == null
        ? valueText
        : TextButton(
            key: widget.valueKey,
            onPressed: _handleDirectEntry,
            style: TextButton.styleFrom(
              foregroundColor: valueColor,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: const RoundedRectangleBorder(
                borderRadius: appButtonRadius,
              ),
            ),
            child: valueText,
          );

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(widget.label, style: AppTypography.bodyMedium),
              const Spacer(),
              valueWidget,
            ],
          ),
          SliderTheme(
            data: _cachedSliderTheme ??= SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.surfaceElevated.withValues(
                alpha: 0.55,
              ),
            ),
            child: Slider(
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              value: _draftValue,
              onChanged: (value) {
                setState(() {
                  _dragging = true;
                  _draftValue = value;
                });
              },
              onChangeEnd: (value) {
                setState(() {
                  _dragging = false;
                  _draftValue = value;
                });
                if ((widget.value - value).abs() <= _epsilon) {
                  return;
                }
                widget.onChangedCommitted(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}
