import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/game_info.dart';
import '../theme/app_colors.dart';
import '../utils/platform_icon.dart';

enum PlatformChipSize {
  sm(frame: 20, radius: 5, glyph: 12),
  md(frame: 24, radius: 6, glyph: 14),
  lg(frame: 32, radius: 8, glyph: 18),
  xl(frame: 48, radius: 10, glyph: 28);

  const PlatformChipSize({
    required this.frame,
    required this.radius,
    required this.glyph,
  });

  final double frame;
  final double radius;
  final double glyph;
}

/// Monotone rounded-square chip showing the platform glyph.
///
/// Uses a subtle dark frame with a warm sand-toned glyph so the chip reads on
/// both the app's dark navy surfaces and over bright cover art without
/// introducing competing color.
class PlatformChip extends StatelessWidget {
  const PlatformChip({
    required this.platform,
    this.size = PlatformChipSize.md,
    this.tooltip,
    this.semanticLabel,
    super.key,
  });

  static const Color _frameFill = Color(0xCC121B24);
  static const Color _frameBorder = Color(0x33FFFFFF);
  static const Color _glyphColor = AppColors.desertSand;
  static const ColorFilter _glyphFilter = ColorFilter.mode(
    _glyphColor,
    BlendMode.srcIn,
  );

  final Platform platform;
  final PlatformChipSize size;
  final String? tooltip;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      width: size.frame,
      height: size.frame,
      decoration: BoxDecoration(
        color: _frameFill,
        borderRadius: BorderRadius.circular(size.radius),
        border: Border.all(color: _frameBorder, width: 1),
      ),
      alignment: Alignment.center,
      child: SvgPicture.asset(
        platformGlyphAsset(platform),
        width: size.glyph,
        height: size.glyph,
        colorFilter: _glyphFilter,
        semanticsLabel: semanticLabel,
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: chip);
    }
    return chip;
  }
}
