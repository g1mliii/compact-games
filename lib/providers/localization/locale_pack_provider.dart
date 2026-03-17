import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_locale.dart';
import '../../services/locale_pack_persistence.dart';

final localePackPersistenceProvider = Provider<LocalePackPersistence>((ref) {
  return const LocalePackPersistence();
});

final installedLocalePackTagsProvider =
    AsyncNotifierProvider<InstalledLocalePackTagsNotifier, Set<String>>(
      InstalledLocalePackTagsNotifier.new,
    );

final selectableAppLocaleDefinitionsProvider =
    Provider<List<AppLocaleDefinition>>((ref) {
      return buildSelectableAppLocaleDefinitions();
    });

final installableAppLocaleDefinitionsProvider =
    Provider<List<AppLocaleDefinition>>((ref) {
      final installedPackTags =
          ref.watch(installedLocalePackTagsProvider).valueOrNull ??
          const <String>{};
      return buildInstallableAppLocaleDefinitions(
        installedPackTags: installedPackTags,
      );
    });

class InstalledLocalePackTagsNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    return ref.read(localePackPersistenceProvider).loadInstalledPackTags();
  }

  Future<void> markInstalled(String localeTag) async {
    final current = Set<String>.from(await future);
    final canonical = canonicalLocaleTag(localeTag);
    final definition = appLocaleDefinitionForTag(canonical);
    if (canonical == null || definition == null || definition.isBundled) {
      return;
    }

    if (!current.add(canonical)) {
      return;
    }
    await _persist(current);
  }

  Future<void> markRemoved(String localeTag) async {
    final current = Set<String>.from(await future);
    final canonical = canonicalLocaleTag(localeTag);
    if (canonical == null || !current.remove(canonical)) {
      return;
    }
    await _persist(current);
  }

  Future<void> _persist(Set<String> tags) async {
    state = AsyncValue.data(Set<String>.unmodifiable(tags));
    await ref.read(localePackPersistenceProvider).saveInstalledPackTags(tags);
  }
}
