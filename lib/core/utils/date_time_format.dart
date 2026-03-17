import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String formatLocalTimestampMinutes(
  DateTime value, {
  Locale locale = const Locale('en'),
}) {
  final formatter = DateFormat('yyyy-MM-dd HH:mm', locale.toLanguageTag());
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
  final monthDay = DateFormat.MMMd(localeTag).format(local);
  final time = DateFormat.Hm(localeTag).format(local);
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
