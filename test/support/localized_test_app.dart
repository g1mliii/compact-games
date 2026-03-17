import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressplay/core/localization/app_locale.dart';
import 'package:pressplay/l10n/app_localizations.dart';

Widget buildLocalizedTestApp({
  required Widget home,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: appSupportedLocales,
    theme: theme,
    home: home,
  );
}

Future<void> pumpLocalizedTestApp(
  WidgetTester tester, {
  required Widget home,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    buildLocalizedTestApp(home: home, locale: locale, theme: theme),
  );
  await tester.pump();
}
