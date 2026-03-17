import 'package:flutter/material.dart';
import 'package:pressplay/l10n/app_localizations.dart';

enum AppLocaleAvailability { bundled, pack }

@immutable
class AppLocaleDefinition {
  const AppLocaleDefinition({
    required this.tag,
    required this.locale,
    required this.availability,
    required this.englishName,
    required this.nativeName,
    this.aliases = const <String>[],
  });

  final String tag;
  final Locale locale;
  final AppLocaleAvailability availability;
  final String englishName;
  final String nativeName;
  final List<String> aliases;

  bool get isBundled => availability == AppLocaleAvailability.bundled;
  bool get isPackBacked => availability == AppLocaleAvailability.pack;

  bool matchesTag(String normalizedTag) {
    if (normalizeLocaleTag(tag) == normalizedTag) {
      return true;
    }
    for (final alias in aliases) {
      if (normalizeLocaleTag(alias) == normalizedTag) {
        return true;
      }
    }
    return false;
  }
}

const Locale _englishLocale = Locale('en');

const AppLocaleDefinition _englishAppLocale = AppLocaleDefinition(
  tag: 'en',
  locale: Locale('en'),
  availability: AppLocaleAvailability.bundled,
  englishName: 'English',
  nativeName: 'English',
);

const AppLocaleDefinition _spanishAppLocale = AppLocaleDefinition(
  tag: 'es',
  locale: Locale('es'),
  availability: AppLocaleAvailability.bundled,
  englishName: 'Spanish',
  nativeName: 'Español',
  aliases: <String>['es-ES', 'es-MX', 'es-419'],
);

const AppLocaleDefinition _simplifiedChineseAppLocale = AppLocaleDefinition(
  tag: 'zh-CN',
  locale: Locale('zh'),
  availability: AppLocaleAvailability.bundled,
  englishName: 'Chinese (Simplified)',
  nativeName: '简体中文',
  aliases: <String>['zh', 'zh-Hans', 'zh-SG'],
);

const AppLocaleDefinition _brazilianPortuguesePackLocale = AppLocaleDefinition(
  tag: 'pt-BR',
  locale: Locale('pt', 'BR'),
  availability: AppLocaleAvailability.pack,
  englishName: 'Portuguese (Brazil)',
  nativeName: 'Português (Brasil)',
  aliases: <String>['pt'],
);

const AppLocaleDefinition _germanPackLocale = AppLocaleDefinition(
  tag: 'de',
  locale: Locale('de'),
  availability: AppLocaleAvailability.pack,
  englishName: 'German',
  nativeName: 'Deutsch',
);

const AppLocaleDefinition _frenchPackLocale = AppLocaleDefinition(
  tag: 'fr',
  locale: Locale('fr'),
  availability: AppLocaleAvailability.pack,
  englishName: 'French',
  nativeName: 'Français',
);

const List<AppLocaleDefinition> appLocaleCatalog = <AppLocaleDefinition>[
  _englishAppLocale,
  _spanishAppLocale,
  _simplifiedChineseAppLocale,
  _brazilianPortuguesePackLocale,
  _germanPackLocale,
  _frenchPackLocale,
];

final List<Locale> appSupportedLocales = List<Locale>.unmodifiable(
  appLocaleCatalog
      .where((definition) => definition.isBundled)
      .map((definition) => definition.locale),
);

final List<AppLocaleDefinition> _cachedSelectableDefinitions =
    List<AppLocaleDefinition>.unmodifiable(
      appLocaleCatalog.where((definition) => definition.isBundled),
    );

List<AppLocaleDefinition> buildSelectableAppLocaleDefinitions() {
  return _cachedSelectableDefinitions;
}

List<AppLocaleDefinition> buildInstallableAppLocaleDefinitions({
  Set<String> installedPackTags = const <String>{},
}) {
  final normalizedInstalled = _normalizeTagSet(installedPackTags);
  return List<AppLocaleDefinition>.unmodifiable(
    appLocaleCatalog.where(
      (definition) =>
          definition.isPackBacked &&
          !normalizedInstalled.contains(definition.tag),
    ),
  );
}

String? canonicalLocaleTag(String? value) {
  final definition = appLocaleDefinitionForTag(value);
  return definition?.tag ?? normalizeLocaleTag(value);
}

String? normalizeLocaleTag(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final rawParts = trimmed
      .replaceAll('_', '-')
      .split('-')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (rawParts.isEmpty) {
    return null;
  }

  final languageCode = rawParts.first.toLowerCase();
  if (languageCode.isEmpty) {
    return null;
  }

  String? scriptCode;
  String? countryCode;
  if (rawParts.length >= 2) {
    final second = rawParts[1];
    if (second.length == 4) {
      scriptCode = _toTitleCase(second);
    } else {
      countryCode = second.toUpperCase();
    }
  }
  if (rawParts.length >= 3) {
    countryCode = rawParts[2].toUpperCase();
  }

  final parts = <String>[languageCode];
  if (scriptCode != null && scriptCode.isNotEmpty) {
    parts.add(scriptCode);
  }
  if (countryCode != null && countryCode.isNotEmpty) {
    parts.add(countryCode);
  }
  return parts.join('-');
}

Locale? parseLocaleTag(String? value) {
  final normalized = normalizeLocaleTag(value);
  if (normalized == null) {
    return null;
  }

  final parts = normalized.split('-');
  if (parts.length == 1) {
    return Locale(parts[0]);
  }
  if (parts.length == 2) {
    final second = parts[1];
    if (second.length == 4) {
      return Locale.fromSubtags(languageCode: parts[0], scriptCode: second);
    }
    return Locale(parts[0], second);
  }
  return Locale.fromSubtags(
    languageCode: parts[0],
    scriptCode: parts[1],
    countryCode: parts[2],
  );
}

String localeTagFor(Locale locale) {
  final parts = <String>[locale.languageCode.toLowerCase()];
  final scriptCode = locale.scriptCode;
  if (scriptCode != null && scriptCode.isNotEmpty) {
    parts.add(_toTitleCase(scriptCode));
  }
  final countryCode = locale.countryCode;
  if (countryCode != null && countryCode.isNotEmpty) {
    parts.add(countryCode.toUpperCase());
  }
  return parts.join('-');
}

AppLocaleDefinition? appLocaleDefinitionForTag(String? value) {
  final normalized = normalizeLocaleTag(value);
  if (normalized == null) {
    return null;
  }

  final parsed = parseLocaleTag(normalized);
  AppLocaleDefinition? languageCodeMatch;
  for (final definition in appLocaleCatalog) {
    if (definition.matchesTag(normalized)) {
      return definition;
    }
    if (languageCodeMatch == null &&
        parsed != null &&
        definition.locale.languageCode == parsed.languageCode) {
      languageCodeMatch = definition;
    }
  }
  return languageCodeMatch;
}

Locale resolveSupportedAppLocale({
  required String? preferredLocaleTag,
  required Locale? systemLocale,
}) {
  final selectableDefinitions = buildSelectableAppLocaleDefinitions();

  final preferredDefinition = _matchSelectableDefinitionForTag(
    preferredLocaleTag,
    selectableDefinitions,
  );
  if (preferredDefinition != null) {
    return preferredDefinition.locale;
  }

  final systemDefinition = _matchSelectableDefinitionForLocale(
    systemLocale,
    selectableDefinitions,
  );
  if (systemDefinition != null) {
    return systemDefinition.locale;
  }

  return _englishLocale;
}

String labelForAppLocale(
  AppLocalizations l10n,
  AppLocaleDefinition definition,
) {
  return switch (definition.tag) {
    'en' => l10n.settingsLanguageEnglish,
    'es' => l10n.settingsLanguageSpanish,
    'zh-CN' => l10n.settingsLanguageChineseSimplified,
    _ => definition.nativeName,
  };
}

AppLocaleDefinition? selectableAppLocaleDefinitionForTag(
  String? value,
  List<AppLocaleDefinition> selectableDefinitions,
) {
  return _matchSelectableDefinitionForTag(value, selectableDefinitions);
}

AppLocaleDefinition? _matchSelectableDefinitionForTag(
  String? value,
  List<AppLocaleDefinition> selectableDefinitions,
) {
  final normalized = normalizeLocaleTag(value);
  if (normalized == null) {
    return null;
  }
  for (final definition in selectableDefinitions) {
    if (definition.matchesTag(normalized)) {
      return definition;
    }
  }
  return null;
}

AppLocaleDefinition? _matchSelectableDefinitionForLocale(
  Locale? locale,
  List<AppLocaleDefinition> selectableDefinitions,
) {
  if (locale == null) {
    return null;
  }

  final exactTag = localeTagFor(locale);
  final exact = _matchSelectableDefinitionForTag(
    exactTag,
    selectableDefinitions,
  );
  if (exact != null) {
    return exact;
  }

  for (final definition in selectableDefinitions) {
    if (definition.locale.languageCode == locale.languageCode) {
      return definition;
    }
  }
  return null;
}

Set<String> _normalizeTagSet(Set<String> tags) {
  final normalized = <String>{};
  for (final tag in tags) {
    final canonical = canonicalLocaleTag(tag);
    if (canonical != null) {
      normalized.add(canonical);
    }
  }
  return normalized;
}

String _toTitleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1).toLowerCase();
}
