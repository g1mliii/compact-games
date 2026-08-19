import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Formatters by locale tag.
///
/// Building a [NumberFormat] resolves the locale and parses a pattern, which is
/// wasted work when these are called from a list item's `build`. The app ships
/// three locales, so the map cannot grow unbounded.
final Map<String, NumberFormat> _decimalFormats = <String, NumberFormat>{};

/// Groups the digits for the locale: `814,354` rather than `814354`.
String formatGroupedInteger(int value, {Locale locale = const Locale('en')}) {
  final localeTag = locale.toLanguageTag();
  final formatter = _decimalFormats.putIfAbsent(
    localeTag,
    () => NumberFormat.decimalPattern(localeTag),
  );
  return formatter.format(value);
}
