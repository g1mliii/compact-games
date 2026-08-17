import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Formatters by locale tag.
///
/// Building a [DateFormat] resolves the locale and parses a pattern, which is
/// wasted work when these are called from a list item's `build`. The app ships
/// three locales, so the map cannot grow unbounded.
final Map<String, DateFormat> _timestampMinutes = <String, DateFormat>{};
final Map<String, DateFormat> _monthDay = <String, DateFormat>{};
final Map<String, DateFormat> _hourMinute = <String, DateFormat>{};

String formatLocalTimestampMinutes(
  DateTime value, {
  Locale locale = const Locale('en'),
}) {
  final formatter = _timestampMinutes.putIfAbsent(
    locale.toLanguageTag(),
    () => DateFormat('yyyy-MM-dd HH:mm', locale.toLanguageTag()),
  );
  return formatter.format(value.toLocal());
}

String? formatLocalTimestampMinutesOrNull(
  DateTime? value, {
  Locale locale = const Locale('en'),
}) {
  if (value == null) {
    return null;
  }
  return formatLocalTimestampMinutes(value, locale: locale);
}

String formatLocalMonthDayTime(
  DateTime value, {
  Locale locale = const Locale('en'),
}) {
  final localeTag = locale.toLanguageTag();
  final local = value.toLocal();
  final monthDay = _monthDay
      .putIfAbsent(localeTag, () => DateFormat.MMMd(localeTag))
      .format(local);
  final time = _hourMinute
      .putIfAbsent(localeTag, () => DateFormat.Hm(localeTag))
      .format(local);
  return '$monthDay, $time';
}

String? formatLocalMonthDayTimeOrNull(
  DateTime? value, {
  Locale locale = const Locale('en'),
}) {
  if (value == null) {
    return null;
  }
  return formatLocalMonthDayTime(value, locale: locale);
}
