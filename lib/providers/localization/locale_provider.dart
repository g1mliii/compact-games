import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_locale.dart';
import '../../core/localization/app_localization.dart';
import '../../providers/settings/settings_provider.dart';

final systemLocaleControllerProvider =
    ChangeNotifierProvider<SystemLocaleController>((ref) {
      return SystemLocaleController();
    });

final effectiveLocaleProvider = Provider<Locale>((ref) {
  final preferredLocaleTag = ref.watch(
    settingsProvider.select((s) => s.valueOrNull?.settings.localeTag),
  );
  final systemLocale = ref.watch(
    systemLocaleControllerProvider.select((controller) => controller.locale),
  );
  return resolveSupportedAppLocale(
    preferredLocaleTag: preferredLocaleTag,
    systemLocale: systemLocale,
  );
});

final appLocalizationsProvider = Provider((ref) {
  final locale = ref.watch(effectiveLocaleProvider);
  return appLocalizationsForLocale(locale);
});

class SystemLocaleController extends ChangeNotifier
    with WidgetsBindingObserver {
  SystemLocaleController() : _locale = _readSystemLocale() {
    WidgetsBinding.instance.addObserver(this);
  }

  Locale _locale;

  Locale get locale => _locale;

  @override
  void didChangeLocales(List<Locale>? locales) {
    final nextLocale = _selectFirstLocale(locales);
    if (_locale == nextLocale) {
      return;
    }
    _locale = nextLocale;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static Locale _readSystemLocale() {
    return _selectFirstLocale(ui.PlatformDispatcher.instance.locales);
  }

  static Locale _selectFirstLocale(List<Locale>? locales) {
    final locale = locales != null && locales.isNotEmpty
        ? locales.first
        : ui.PlatformDispatcher.instance.locale;
    if (locale.languageCode.isNotEmpty) {
      return locale;
    }
    return const Locale('en');
  }
}
