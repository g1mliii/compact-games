import 'package:shared_preferences/shared_preferences.dart';

import '../core/localization/app_locale.dart';

const _installedLocalePackTagsKey = 'compact_games_installed_locale_pack_tags_v1';

/// Persists the set of installed non-bundled locale-pack tags.
///
/// This does not load translation content yet. It exists so future locale-pack
/// installation can slot into the current locale registry without revisiting
/// settings persistence or selector wiring.
class LocalePackPersistence {
  const LocalePackPersistence();

  static final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  Future<Set<String>> loadInstalledPackTags() async {
    try {
      final prefs = await _prefsFuture;
      final rawTags =
          prefs.getStringList(_installedLocalePackTagsKey) ?? const <String>[];
      final installed = <String>{};
      for (final rawTag in rawTags) {
        final canonical = canonicalLocaleTag(rawTag);
        final definition = appLocaleDefinitionForTag(canonical);
        if (canonical == null || definition == null || definition.isBundled) {
          continue;
        }
        installed.add(canonical);
      }
      return installed;
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> saveInstalledPackTags(Set<String> tags) async {
    try {
      final prefs = await _prefsFuture;
      final sanitized = <String>[];
      for (final tag in tags) {
        final canonical = canonicalLocaleTag(tag);
        final definition = appLocaleDefinitionForTag(canonical);
        if (canonical == null || definition == null || definition.isBundled) {
          continue;
        }
        sanitized.add(canonical);
      }
      sanitized.sort();
      await prefs.setStringList(_installedLocalePackTagsKey, sanitized);
    } catch (_) {
      // Locale-pack installation state is additive metadata only.
    }
  }
}
