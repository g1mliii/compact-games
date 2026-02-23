import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../theme/app_colors.dart';

/// Warms up common PressPlay gradients, rounded clips, and strokes so
/// first-interaction rasterization is less likely to hitch on cold shader cache.
class PressPlayShaderWarmUp extends ShaderWarmUp {
  const PressPlayShaderWarmUp();

  @override
  ui.Size get size => const ui.Size(220, 220);

  @override
  Future<void> warmUpOnCanvas(ui.Canvas canvas) async {
    const rect = ui.Rect.fromLTWH(0, 0, 220, 220);
    final shell = ui.RRect.fromRectAndRadius(
      rect.deflate(8),
      const ui.Radius.circular(16),
    );

    canvas.drawRRect(
      shell,
      ui.Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, const [
          AppColors.surfaceVariant,
          AppColors.surface,
        ]),
    );

    canvas.drawRRect(
      shell,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.border,
    );

    canvas.save();
    canvas.clipRRect(shell);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 220, 136),
      ui.Paint()
        ..shader = ui.Gradient.linear(
          const ui.Offset(0, 0),
          const ui.Offset(0, 136),
          const [AppColors.deepHorizonBlue, AppColors.nightDune],
        ),
    );
    canvas.restore();

    const trackRect = ui.Rect.fromLTWH(24, 170, 172, 8);
    final track = ui.RRect.fromRectAndRadius(
      trackRect,
      const ui.Radius.circular(4),
    );
    canvas.drawRRect(track, ui.Paint()..color = AppColors.surfaceElevated);

    const fillRect = ui.Rect.fromLTWH(24, 170, 120, 8);
    final fill = ui.RRect.fromRectAndRadius(
      fillRect,
      const ui.Radius.circular(4),
    );
    canvas.drawRRect(
      fill,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          fillRect.topLeft,
          fillRect.topRight,
          const [AppColors.desertGold, AppColors.burntSienna],
        ),
    );
  }
}
