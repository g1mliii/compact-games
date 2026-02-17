import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

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
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double value) valueLabelBuilder;
  final ValueChanged<double> onChangedCommitted;

  @override
  State<SettingsSliderRow> createState() => _SettingsSliderRowState();
}

class _SettingsSliderRowState extends State<SettingsSliderRow> {
  static const double _epsilon = 0.001;
  late double _draftValue;
  bool _dragging = false;

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

  @override
  Widget build(BuildContext context) {
    final valueLabel = widget.valueLabelBuilder(_draftValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label, style: AppTypography.bodyMedium),
            const Spacer(),
            Text(valueLabel, style: AppTypography.bodySmall),
          ],
        ),
        Slider(
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
      ],
    );
  }
}
