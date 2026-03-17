import 'package:flutter/widgets.dart';
import 'package:pressplay/l10n/app_localizations.dart';

extension BuildContextLocalizationX on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? lookupAppLocalizations(const Locale('en'));
}

AppLocalizations appLocalizationsForLocale(Locale locale) {
  return lookupAppLocalizations(locale);
}
