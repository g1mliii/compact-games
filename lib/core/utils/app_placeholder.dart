import 'dart:ui';

/// Deterministic color palette for application placeholder icons.
///
/// Colors are muted tones from the desert theme, designed for dark backgrounds.
class AppPlaceholder {
  AppPlaceholder._();

  static const List<Color> palette = [
    Color(0xFF4A6B8A), // deep steel blue
    Color(0xFF8A6B4A), // warm bronze
    Color(0xFF6B8A5A), // sage green
    Color(0xFF8A5A6B), // dusty mauve
    Color(0xFF5A8A7A), // teal
    Color(0xFF7A6B8A), // muted purple
    Color(0xFF8A7A5A), // desert tan
    Color(0xFF5A6B8A), // slate blue
  ];

  static Color colorForPath(String path) {
    return palette[(path.hashCode & 0x7FFFFFFF) % palette.length];
  }
}
