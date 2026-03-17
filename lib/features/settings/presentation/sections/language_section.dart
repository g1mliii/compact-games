import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/localization/app_locale.dart';
import '../../../../core/localization/app_localization.dart';
import '../../../../providers/localization/locale_pack_provider.dart';
import '../../../../providers/settings/settings_provider.dart';
import '../widgets/settings_section_card.dart';
import '../widgets/static_popup_selector.dart';

const ValueKey<String> _languageSelectorKey = ValueKey<String>(
  'settingsLanguageSelector',
);

class LanguageSection extends ConsumerWidget {
  const LanguageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeTag = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.settings.localeTag),
    );
    final selectableLocales = ref.watch(selectableAppLocaleDefinitionsProvider);
    final l10n = context.l10n;
    final selectedDefinition = selectableAppLocaleDefinitionForTag(
      localeTag,
      selectableLocales,
    );
    final selectedLabel = selectedDefinition == null
        ? l10n.settingsLanguageSystemDefault
        : labelForAppLocale(l10n, selectedDefinition);

    return SettingsSectionCard(
      icon: LucideIcons.languages,
      title: l10n.settingsLanguageSectionTitle,
      child: RepaintBoundary(
        child: SizedBox(
          key: _languageSelectorKey,
          child: StaticPopupSelector<String?>(
            labelText: l10n.settingsLanguageSelectorLabel,
            tooltip: l10n.settingsLanguageSelectorTooltip,
            selectedLabel: selectedLabel,
            items: <StaticPopupSelectorItem<String?>>[
              StaticPopupSelectorItem<String?>(
                value: null,
                label: l10n.settingsLanguageSystemDefault,
                selected: canonicalLocaleTag(localeTag) == null,
              ),
              ...selectableLocales.map(
                (definition) => StaticPopupSelectorItem<String?>(
                  value: definition.tag,
                  label: labelForAppLocale(l10n, definition),
                  selected: definition.tag == canonicalLocaleTag(localeTag),
                ),
              ),
            ],
            onSelected: (value) =>
                ref.read(settingsProvider.notifier).setLocaleTag(value),
          ),
        ),
      ),
    );
  }
}
